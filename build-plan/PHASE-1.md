# Phase 1: 构建上下文与多架构环境初始化

## 目标
定义核心构建参数，建立能够自动感知并适配 `amd64` 与 `arm64` 架构的基础环境。

## 详细计划
1.  **定义构建参数 (ARG)**：
    *   `USE_CHINA_MIRROR`: 核心开关，默认 `false`。
    *   `APT_MIRROR_NAME`: 镜像商名称（如 `aliyun`, `tsinghua`）。
    *   `NPM_REGISTRY`: 用于安装特定组件的 npm 源。
    *   `MISE_VERSION`: 固定 mise 版本，确保构建可重现。
2.  **架构映射逻辑**：
    *   在 Dockerfile 中利用 `dpkg --print-architecture` 获取当前容器架构。
    *   根据架构设置变量，决定后续阶段使用的镜像子路径（特别是针对 Ubuntu Ports）。
3.  **基础环境变量配置**：
    *   设置 `MISE_DATA_DIR`, `MISE_CONFIG_DIR`, `MISE_CACHE_DIR` 等路径。
    *   预配置 `PATH` 包含 mise 的 shims 目录。

## Checklist
- [ ] `USE_CHINA_MIRROR` 是否作为可选参数并在后续逻辑中被引用？
- [ ] 是否正确识别了 `arm64` 架构并能对应到 `ubuntu-ports` 镜像地址？
- [ ] 环境变量是否确保了路径的解耦（避免硬编码 `/root`）？

## 验证方法
执行以下构建命令并检查输出：
```bash
docker build --build-arg USE_CHINA_MIRROR=true -t test-phase-1 -f docker/Dockerfile .
```
在构建日志中寻找：
- `dpkg --print-architecture` 的输出。
- `USE_CHINA_MIRROR` 的生效状态。
