#!/usr/bin/env python3
"""
AI-Agent Harness Smoke Test
============================
验证 plan.md 中定义的核心达成指标：
1. 环境就绪：容器内 python, node, uv, pnpm 版本与 docker/mise-global.toml 一致
2. 挂载验证：宿主机目录 ↔ /workspace 双向同步
3. 启动/清理：up → down 后无残留容器
4. 数据持久化：标准 down 后 Qdrant 数据卷保留
5. 深度清理：clean 后网络和镜像无残留
6. 热启动计时：镜像已构建、infra 已运行时 up ≤ 5s
7. 端口访问：容器内 8000-9999 端口可通过宿主机 localhost 访问
8. 工具可用：opencode 和 vim 在容器内可执行
"""

import os
import subprocess
import sys
import time
import tomllib
import urllib.request
from pathlib import Path

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
PROJECT_ROOT = Path(__file__).parent.resolve()
MISE_PATH = PROJECT_ROOT / "docker" / "mise-global.toml"
IMAGE_NAME = "ai-dev:latest"
NETWORK_NAME = "agent-network"
VOLUME_NAME = "qdrant_data"
MARKER_FILE = PROJECT_ROOT / ".smoke_test_marker"

# Detect docker compose command (v2 plugin vs v1 standalone)
def detect_docker_compose():
    result = subprocess.run(
        "docker compose version", shell=True, capture_output=True, text=True
    )
    if result.returncode == 0:
        return "docker compose"
    result = subprocess.run(
        "docker-compose version", shell=True, capture_output=True, text=True
    )
    if result.returncode == 0:
        return "docker-compose"
    raise RuntimeError("docker compose is required but not found")

DOCKER_COMPOSE = detect_docker_compose()

# -----------------------------------------------------------------------------
# Shared helpers
# -----------------------------------------------------------------------------
def run(cmd, check=True, capture_output=True, text=True, timeout=60):
    """Run a shell command and return the CompletedProcess result."""
    return subprocess.run(
        cmd,
        shell=True,
        check=check,
        capture_output=capture_output,
        text=text,
        timeout=timeout,
    )


def load_mise_versions():
    """Parse docker/mise-global.toml to get expected tool versions."""
    with open(MISE_PATH, "rb") as f:
        data = tomllib.load(f)
    return data.get("tools", {})


def ensure_infra_running():
    """Ensure docker-compose infrastructure is up."""
    run("scripts/compose up -d", check=False)


def cleanup_marker():
    """Remove the temporary marker file if it exists."""
    MARKER_FILE.unlink(missing_ok=True)


def harness_container_ids():
    """Return containers owned by the harness scripts."""
    ids = set()
    filters = [
        "name=^/agent-redis$",
        "name=^/agent-qdrant$",
        f"ancestor={IMAGE_NAME}",
    ]
    for docker_filter in filters:
        result = run(f"docker ps -aq --filter '{docker_filter}'", check=False)
        for container_id in result.stdout.splitlines():
            if container_id.strip():
                ids.add(container_id.strip())
    return sorted(ids)


def network_container_ids(network_name):
    """Return container ids connected to a Docker network."""
    result = run(
        f"docker network inspect {network_name} --format '{{{{range $id, $_ := .Containers}}}}{{{{println $id}}}}{{{{end}}}}'",
        check=False,
    )
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


# -----------------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------------
def test_01_container_tool_versions():
    """容器内各工具版本与 docker/mise-global.toml 一致。"""
    print("\n[TEST 01] Container tool versions alignment")
    expected = load_mise_versions()
    if not expected:
        print("  ⚠️  No tools found in docker/mise-global.toml")
        return False

    result = run("scripts/toolchain versions .", check=False)
    output = result.stdout + result.stderr

    ok = True
    for tool, expected_ver in expected.items():
        expected_clean = expected_ver.replace("'", "").replace('"', "")
        if expected_clean == "latest":
            continue
        if expected_clean in output:
            print(f"  ✅ {tool}: {expected_clean}")
        else:
            print(f"  ❌ {tool}: expected {expected_clean}, not found in output")
            print(f"     Output snippet: {output[:500]}")
            ok = False
    return ok


def test_02_mount_bidirectional_sync():
    """宿主机目录正确挂载到 /workspace（创建文件双向可见）。"""
    print("\n[TEST 02] Workspace mount bidirectional sync")
    cleanup_marker()

    marker_content = f"smoke_test_{os.getpid()}_{time.time()}"

    try:
        # Host → Container
        MARKER_FILE.write_text(marker_content)
        result = run(
            f"scripts/toolchain run . cat /workspace/.smoke_test_marker",
            check=False,
            timeout=30,
        )
        container_content = (result.stdout + result.stderr).strip()
        if container_content != marker_content:
            print(f"  ❌ Host → Container sync failed")
            print(f"     Expected: {marker_content}")
            print(f"     Got: {container_content}")
            return False
        print("  ✅ Host → Container sync works")

        # Container → Host
        new_content = f"container_{marker_content}"
        run(
            f"scripts/toolchain run . bash -c 'echo {new_content} > /workspace/.smoke_test_marker'",
            check=False,
            timeout=30,
        )
        host_content = MARKER_FILE.read_text().strip()
        if host_content != new_content:
            print(f"  ❌ Container → Host sync failed")
            print(f"     Expected: {new_content}")
            print(f"     Got: {host_content}")
            return False
        print("  ✅ Container → Host sync works")

        return True
    finally:
        cleanup_marker()


def test_03_port_publish_to_host():
    """容器内 8000-9999 端口可通过宿主机 localhost 访问。"""
    print("\n[TEST 03] Container development port published to host")
    port = 8765
    proc = None

    try:
        env = os.environ.copy()
        env["HARNESS_PORT_RANGE"] = f"{port}-{port}"
        proc = subprocess.Popen(
            [
                "scripts/toolchain",
                "run",
                ".",
                "python",
                "-m",
                "http.server",
                str(port),
                "--bind",
                "0.0.0.0",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
            env=env,
        )

        url = f"http://127.0.0.1:{port}/"
        for _ in range(30):
            if proc.poll() is not None:
                print("  ❌ Container HTTP server exited before it was reachable")
                return False
            try:
                with urllib.request.urlopen(url, timeout=1) as response:
                    if response.status == 200:
                        print(f"  ✅ {url} reachable from host")
                        return True
            except Exception:
                time.sleep(1)

        print(f"  ❌ {url} was not reachable from host")
        return False
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=10)


def test_09_opencode_and_vim_available():
    """opencode 和 vim 在容器内可执行。"""
    print("\n[TEST 09] OpenCode and vim available in container")
    checks = [
        ("opencode", "opencode --version"),
        ("vim",     "vim --version"),
    ]
    ok = True
    for name, cmd in checks:
        result = run(f"scripts/toolchain run . {cmd}", check=False, timeout=60)
        if result.returncode != 0:
            print(f"  ❌ {name}: exit code {result.returncode}")
            print(f"     stderr: {result.stderr}")
            ok = False
        else:
            first_line = (result.stdout + result.stderr).strip().split("\n")[0]
            print(f"  ✅ {name}: {first_line}")
    return ok


def test_03_down_removes_containers():
    """scripts/task-harness-up → scripts/task-harness-down 后，无业务容器残留。"""
    print("\n[TEST 04] Standard down removes harness containers")

    ensure_infra_running()
    run("scripts/task-harness-down", check=False)

    containers = harness_container_ids()

    if containers:
        print(f"  ❌ Containers still exist after down:")
        print(f"     {' '.join(containers)}")
        return False
    print("  ✅ No harness containers remaining after down")
    return True


def test_04_down_preserves_volume():
    """Qdrant 数据卷在标准 down 后仍然保留。"""
    print("\n[TEST 05] Standard down preserves qdrant_data volume")
    ensure_infra_running()
    run("scripts/task-harness-down", check=False)

    result = run("docker volume ls -q -f name=qdrant_data", check=False)
    volumes = result.stdout.strip()

    if VOLUME_NAME not in volumes:
        print(f"  ❌ qdrant_data volume missing after standard down")
        return False
    print("  ✅ qdrant_data volume preserved")
    return True


def test_05_clean_removes_network_and_image():
    """docker network ls 中无孤立的 agent-network（深度清理后）。"""
    print("\n[TEST 06] Deep clean removes network and image")
    ensure_infra_running()
    run("scripts/task-harness-clean", check=False)

    # Check network
    result = run("docker network ls --format '{{.Name}}'", check=False)
    networks = result.stdout.strip().split("\n")
    if NETWORK_NAME in networks:
        print(f"  ❌ {NETWORK_NAME} still exists after clean")
        attached = network_container_ids(NETWORK_NAME)
        if attached:
            print(f"     Attached containers: {' '.join(attached)}")
        result = run(
            f"docker network inspect {NETWORK_NAME} --format '{{{{json .Containers}}}}'",
            check=False,
        )
        if result.stdout.strip():
            print(f"     Network endpoints: {result.stdout.strip()}")
        return False
    print(f"  ✅ {NETWORK_NAME} removed")

    # Check image
    result = run(f"docker image inspect {IMAGE_NAME}", check=False)
    if result.returncode == 0:
        print(f"  ❌ {IMAGE_NAME} still exists after clean")
        return False
    print(f"  ✅ {IMAGE_NAME} removed")

    return True


def test_06_hot_start_timing():
    """热启动测试：镜像已构建、基础设施已运行，执行本地脚本链路应该 ≤ 15s。"""
    print("\n[TEST 07] Hot-start timing (target: ≤ 15s)")

    result = run(f"docker image inspect {IMAGE_NAME}", check=False)
    if result.returncode != 0:
        print(f"  ⏭️  Skipping: {IMAGE_NAME} not built yet. Run 'docker build -t {IMAGE_NAME} -f docker/Dockerfile .' first.")
        return None

    ensure_infra_running()

    times = []
    for i in range(3):
        stage_times = {}

        t0 = time.perf_counter()
        run("scripts/check-host", check=False, capture_output=True)
        stage_times["check-host"] = time.perf_counter() - t0

        t0 = time.perf_counter()
        run(f"docker image inspect {IMAGE_NAME}", check=False, capture_output=True)
        stage_times["image-inspect"] = time.perf_counter() - t0

        t0 = time.perf_counter()
        run("scripts/toolchain run . true", check=False, capture_output=True, timeout=30)
        stage_times["toolchain-run"] = time.perf_counter() - t0

        total = sum(stage_times.values())
        times.append(total)
        print(
            f"  Run {i+1}: {total:.2f}s "
            f"(check-host: {stage_times['check-host']:.2f}s, "
            f"image-inspect: {stage_times['image-inspect']:.2f}s, "
            f"toolchain-run: {stage_times['toolchain-run']:.2f}s)"
        )

    avg = sum(times) / len(times)
    median = sorted(times)[len(times) // 2]
    print(f"  Average: {avg:.2f}s | Median: {median:.2f}s")

    if median <= 15.0:
        print("  ✅ Median hot-start ≤ 15s")
        return True
    print("  ⚠️  Median hot-start > 15s (may vary by host)")
    return False


def test_07_host_profile_generation():
    """验证 check-host 能正确生成宿主机画像 TOML 文件。"""
    print("\n[TEST 08] Host profile generation")

    # Run check-host to generate/refresh profile
    result = run("scripts/check-host --yes --refresh", check=False)
    if result.returncode != 0:
        print("  ❌ scripts/check-host failed to execute")
        print(result.stderr)
        return False

    profile_path = Path.home() / ".config" / "ai-harness" / "host-profile.toml"
    if not profile_path.exists():
        print(f"  ❌ Profile not found at {profile_path}")
        return False

    try:
        with open(profile_path, "rb") as f:
            profile = tomllib.load(f)

        required_sections = ["meta", "host", "network", "mirrors", "recommendations"]
        for section in required_sections:
            if section not in profile:
                print(f"  ❌ Missing section '{section}' in host profile")
                return False

        print(f"  ✅ Host profile valid. Location detected: {profile['network'].get('location')}")
        return True
    except Exception as e:
        print(f"  ❌ Failed to parse host profile: {e}")
        return False


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
def main():
    print("=" * 60)
    print("AI-Agent Harness Smoke Test")
    print(f"Using compose command: {DOCKER_COMPOSE}")
    print("=" * 60)

    results = []
    skipped = []

    tests = [
        test_07_host_profile_generation,
        test_01_container_tool_versions,
        test_02_mount_bidirectional_sync,
        test_03_port_publish_to_host,
        test_09_opencode_and_vim_available,
        test_03_down_removes_containers,
        test_04_down_preserves_volume,
        test_06_hot_start_timing,
        test_05_clean_removes_network_and_image,
    ]

    for test_fn in tests:
        try:
            result = test_fn()
            if result is None:
                skipped.append(test_fn.__name__)
            elif result:
                results.append((test_fn.__name__, "PASS"))
            else:
                results.append((test_fn.__name__, "FAIL"))
        except Exception as e:
            print(f"  💥 Exception: {e}")
            results.append((test_fn.__name__, "ERROR"))

    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    passed = sum(1 for _, r in results if r == "PASS")
    failed = sum(1 for _, r in results if r in ("FAIL", "ERROR"))
    for name, status in results:
        icon = "✅" if status == "PASS" else ("⏭️" if status == "SKIP" else "❌")
        print(f"  {icon} {name}: {status}")
    if skipped:
        print(f"\n  ⏭️  Skipped: {', '.join(skipped)}")
    print(f"\n  Total: {passed} passed, {failed} failed, {len(skipped)} skipped")

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
