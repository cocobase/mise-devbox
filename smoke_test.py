#!/usr/bin/env python3
"""
AI-Agent Harness Smoke Test
============================
验证 plan.md 中定义的核心达成指标：
1. 环境就绪：容器内 python, node, uv, pnpm 版本与 .mise.toml 一致
2. 挂载验证：宿主机目录 ↔ /workspace 双向同步
3. 启动/清理：up → down 后无残留容器
4. 数据持久化：标准 down 后 Qdrant 数据卷保留
5. 深度清理：clean 后网络和镜像无残留
6. 热启动计时：镜像已构建、infra 已运行时 up ≤ 5s
"""

import os
import subprocess
import sys
import tempfile
import time
import tomllib
from pathlib import Path

# Detect docker compose command (v2 plugin vs v1 standalone)
def detect_docker_compose():
    result = subprocess.run("docker compose version", shell=True, capture_output=True)
    if result.returncode == 0:
        return "docker compose"
    result = subprocess.run("docker-compose version", shell=True, capture_output=True)
    if result.returncode == 0:
        return "docker-compose"
    raise RuntimeError("docker compose is required but not found")

DOCKER_COMPOSE = detect_docker_compose()

# Configuration
IMAGE_NAME = "ai-dev-toolchain:latest"
NETWORK_NAME = "agent-network"
VOLUME_NAME = "qdrant_data"
PROJECT_ROOT = Path(__file__).parent.resolve()

def run(cmd, check=True, capture_output=True, text=True, timeout=60):
    """Run a shell command and return result."""
    result = subprocess.run(
        cmd,
        shell=True,
        check=check,
        capture_output=capture_output,
        text=text,
        timeout=timeout,
    )
    return result

def load_mise_versions():
    """Parse .mise.toml to get expected tool versions."""
    mise_path = PROJECT_ROOT / ".mise.toml"
    with open(mise_path, "rb") as f:
        data = tomllib.load(f)
    return data.get("tools", {})

def test_01_container_tool_versions():
    """1. 容器内各工具版本与 .mise.toml 一致。"""
    print("\n[TEST 01] Container tool versions alignment")
    expected = load_mise_versions()
    if not expected:
        print("  ⚠️  No tools found in .mise.toml")
        return False

    # Run versions command inside container
    result = run("scripts/toolchain versions .", check=False)
    output = result.stdout + result.stderr

    ok = True
    for tool, expected_ver in expected.items():
        # e.g., "python = '3.12.13'" -> look for "python: 3.12.13" in output
        if expected_ver.replace("'", "").replace('"', "") in output:
            print(f"  ✅ {tool}: {expected_ver}")
        else:
            print(f"  ❌ {tool}: expected {expected_ver}, not found in output")
            print(f"     Output snippet: {output[:500]}")
            ok = False
    return ok

def test_02_mount_bidirectional_sync():
    """2. 宿主机目录正确挂载到 /workspace（创建文件双向可见）。"""
    print("\n[TEST 02] Workspace mount bidirectional sync")

    marker_file = PROJECT_ROOT / ".smoke_test_marker"
    marker_content = f"smoke_test_{os.getpid()}_{time.time()}"

    # Clean up any stale marker
    marker_file.unlink(missing_ok=True)

    try:
        # Write from host
        marker_file.write_text(marker_content)

        # Read from container
        result = run(
            f"scripts/toolchain run . cat /workspace/.smoke_test_marker",
            check=False,
            timeout=30,
        )
        container_content = (result.stdout + result.stderr).strip()

        if container_content == marker_content:
            print("  ✅ Host → Container sync works")
        else:
            print(f"  ❌ Host → Container sync failed")
            print(f"     Expected: {marker_content}")
            print(f"     Got: {container_content}")
            return False

        # Write from container
        new_content = f"container_{marker_content}"
        run(
            f"scripts/toolchain run . bash -c 'echo {new_content} > /workspace/.smoke_test_marker'",
            check=False,
            timeout=30,
        )

        host_content = marker_file.read_text().strip()
        if host_content == new_content:
            print("  ✅ Container → Host sync works")
        else:
            print(f"  ❌ Container → Host sync failed")
            print(f"     Expected: {new_content}")
            print(f"     Got: {host_content}")
            return False

        return True
    finally:
        marker_file.unlink(missing_ok=True)

def test_03_down_removes_containers():
    """3. mise run up → mise run down 后，docker ps -a 无残留容器。"""
    print("\n[TEST 03] Standard down removes all containers")

    # Ensure infra is up so we have something to stop
    run(f"{DOCKER_COMPOSE} up -d", check=False)

    # Run down
    run("mise run down", check=False)

    # Check containers
    result = run("docker ps -aq", check=False)
    containers = result.stdout.strip()

    if not containers:
        print("  ✅ docker ps -a is empty after down")
        return True
    else:
        print(f"  ❌ Containers still exist after down:")
        print(f"     {containers}")
        return False

def test_04_down_preserves_volume():
    """4. Qdrant 数据卷在标准 down 后仍然保留。"""
    print("\n[TEST 04] Standard down preserves qdrant_data volume")

    # Ensure infra is up
    run(f"{DOCKER_COMPOSE} up -d", check=False)

    # Run down
    run("mise run down", check=False)

    result = run("docker volume ls -q -f name=qdrant_data", check=False)
    volumes = result.stdout.strip()

    if VOLUME_NAME in volumes:
        print("  ✅ qdrant_data volume preserved")
        return True
    else:
        print(f"  ❌ qdrant_data volume missing after standard down")
        return False

def test_05_clean_removes_network_and_image():
    """5. docker network ls 中无孤立的 agent-network（深度清理后）。"""
    print("\n[TEST 05] Deep clean removes network and image")

    # First bring up infra to ensure network exists
    run(f"{DOCKER_COMPOSE} up -d", check=False)

    # Run clean
    run("mise run clean", check=False)

    # Check network
    result = run("docker network ls --format '{{.Name}}'", check=False)
    networks = result.stdout.strip().split("\n")

    if NETWORK_NAME in networks:
        print(f"  ❌ {NETWORK_NAME} still exists after clean")
        return False
    else:
        print(f"  ✅ {NETWORK_NAME} removed")

    # Check image
    result = run(f"docker image inspect {IMAGE_NAME}", check=False)
    if result.returncode != 0:
        print(f"  ✅ {IMAGE_NAME} removed")
    else:
        print(f"  ❌ {IMAGE_NAME} still exists after clean")
        return False

    return True

def test_06_hot_start_timing():
    """6. 热启动测试：镜像已构建、基础设施已运行，执行 mise run up 应该 ≤ 5s。
       注意：此测试只测量脚本编排到 docker run 的耗时，不阻塞进入 shell。"""
    print("\n[TEST 06] Hot-start timing (target: ≤ 5s)")

    # Pre-condition: image exists and infra is running
    result = run(f"docker image inspect {IMAGE_NAME}", check=False)
    if result.returncode != 0:
        print(f"  ⏭️  Skipping: {IMAGE_NAME} not built yet. Run 'mise run build' first.")
        return None  # Skip

    run(f"{DOCKER_COMPOSE} up -d", check=False)

    # We can't actually run 'mise run up' because it blocks.
    # Instead, measure the equivalent non-blocking steps:
    # check + compose up (already done) + docker run
    times = []
    for i in range(3):
        start = time.perf_counter()
        # Simulate the non-blocking part of up: check + image inspect + docker run --rm
        run("scripts/check-host", check=False, capture_output=True)
        run(f"docker image inspect {IMAGE_NAME}", check=False, capture_output=True)
        # Quick container spin-up with immediate exit
        run("scripts/toolchain run . true", check=False, capture_output=True, timeout=30)
        elapsed = time.perf_counter() - start
        times.append(elapsed)
        print(f"  Run {i+1}: {elapsed:.2f}s")

    avg = sum(times) / len(times)
    median = sorted(times)[len(times) // 2]
    print(f"  Average: {avg:.2f}s | Median: {median:.2f}s")

    if median <= 5.0:
        print("  ✅ Median hot-start ≤ 5s")
        return True
    else:
        print("  ⚠️  Median hot-start > 5s (may vary by host)")
        return False

def main():
    print("=" * 60)
    print("AI-Agent Harness Smoke Test")
    print("=" * 60)

    results = []
    skipped = []

    for test_fn in [
        test_01_container_tool_versions,
        test_02_mount_bidirectional_sync,
        test_03_down_removes_containers,
        test_04_down_preserves_volume,
        test_05_clean_removes_network_and_image,
        test_06_hot_start_timing,
    ]:
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
