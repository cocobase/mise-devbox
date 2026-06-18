# Phase 6: 清理与最终验证

## 目标
缩减镜像体积，确保运行环境的安全性和可用性，完成整体交付。

## 详细计划
1.  **缓存清理**：
    *   删除 `/opt/mise-cache/*` 下的所有下载包和解压残留。
    *   清理 `/tmp` 下的临时文件。
2.  **权限加固**：
    *   确保 `/opt/mise` 和 `/opt/mise-config` 对所有用户具有读/执行权限。
    *   配置 `entrypoint.sh` 以处理初始启动时的环境变量加载。
3.  **烟雾测试 (Smoke Test)**：
    *   运行 `smoke_test.py` 确保 Python 环境正常。
    *   检查 pnpm 能否正确执行 `install`。

## Checklist
- [ ] 镜像体积是否控制在合理范围内（建议对比优化前后的体积）？
- [ ] 权限是否允许非 root 用户执行基础工具？
- [ ] 烟雾测试是否全绿通过？

## 验证方法
1.  对比镜像大小：`docker images | grep ai-dev-toolchain`。
2.  运行自动化测试脚本。
3.  手动尝试 `pnpm install` 一个简单的包验证网络连通性。
