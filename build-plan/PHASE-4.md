# Phase 4: Mise 运行时镜像配置 (Settings)

## 目标
通过注入预设的配置文件，让 mise 自动感知国内下载环境，优化后续工具链的安装速度。

## 详细计划
1.  **配置文件准备**：
    *   维护 `docker/mise-china.toml` 文件。
2.  **注入镜像逻辑**：
    *   设置 `node.mirror_url` 为 `https://npmmirror.com/mirrors/node/`。
    *   设置 `url_replacements`：使用正则重写 `astral-sh/uv` 和 `python-build-standalone` 的下载请求。
3.  **配置生效**：
    *   若 `USE_CHINA_MIRROR=true`，将 `mise-china.toml` 复制或软链接至 `MISE_CONFIG_DIR/config.toml`。

## Checklist
- [ ] `url_replacements` 的正则表达式是否能正确匹配 GitHub 的 release 结构？
- [ ] 配置文件是否被放置在正确的 `MISE_CONFIG_DIR` 下？
- [ ] 是否保留了原有的全局配置（如工具版本号）不被冲突覆盖？

## 验证方法
在镜像构建过程中或完成后执行：
```bash
mise settings
```
确认 `node.mirror_url` 和 `url_replacements` 的值已被正确注入。
