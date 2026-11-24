# Packpier

**简体中文** · [English](README.md)

Packpier 是 Codex 桌面端的 macOS 原生插件管理器：安装、排序、启停和移除插件，并把插件效果直接挂到正在运行的 Codex 窗口里。0.1.28 使用 Swift 原生宿主和原生服务，三个内置插件都不需要安装 Node.js。

![Packpier 插件市场](docs/images/prism-sidebar.png)

## 内置插件

| 插件 | 在 Codex 里可以做什么 |
| --- | --- |
| **P-Sign** | 在左下角显示带状态绿点的 P。把指针移上去，可换壁纸或打开背景设置。 |
| **Prism** | 让同一会话在置顶、项目和最近列表里保持同一种颜色；可按项目聚合置顶会话，也可单独给一个会话选色。 |
| **自定义背景** | 使用本地图片或内置图片，调整遮罩与磨砂，并从收藏或最近使用中重新选图。 |

### Prism

置顶会话按项目分组，标题上的色条标记单条会话，项目行右侧的色块打开项目色板。

<a href="docs/images/prism-sidebar.png"><img src="docs/images/prism-sidebar.png" width="320" alt="Codex 侧栏中按项目分组的置顶会话与彩色标题"></a>

### 自定义背景

同一段对话切换两张壁纸的效果，点图可查看原尺寸。

| 花园与白兔 | 粉色花枝 |
| --- | --- |
| [![花园与白兔壁纸](docs/images/background-garden.jpg)](docs/images/background-garden.jpg) | [![粉色花枝壁纸](docs/images/background-blossoms.jpg)](docs/images/background-blossoms.jpg) |

## 安装

**系统要求：** macOS 14 或更高。0.1.28 发布包为 Apple Silicon（arm64）版本。

1. 打开 [GitHub Releases](https://github.com/JFireworm/packpier/releases/latest)，下载对应的 DMG。
2. 打开 DMG，把 **Packpier.app 拖到同一窗口里的 Applications（应用程序）**。推出磁盘映像后，从「应用程序」打开 Packpier。
3. 插件市场里，绿色表示插件已在 Codex 窗口中运行，空心圆表示等待，红色表示插件报错。点选插件可查看版本、权限和错误原文。

当前构建使用 ad-hoc 签名，**未经 Apple 公证**。如果 macOS 阻止首次打开，请确认文件来自本项目的 GitHub Releases，然后前往「系统设置 → 隐私与安全性」选择「仍要打开」。

首次启动时，Packpier 会把自己注册为登录项。如果 macOS 要求批准，可在「设置与更新 → 打开登录项设置」完成。「自动更新」默认开启，也可以在同一页关闭。

## 连接 Codex

Packpier 通过 Codex 自己的本机 DevTools 端点（`127.0.0.1:9335`）挂载插件，不修改 Codex 应用包，也不写它的配置。

- **Codex 未运行：** Packpier 会带上所需的本机调试参数启动它。
- **Codex 已运行但没有该端点：** 先在 Codex 里保存工作，再点插件市场状态旁的**「重启并连接」**。Packpier 会请求 Codex 正常退出；5 秒内没有退出就强制结束，然后带本机端点重新打开。**未保存的 Codex 会话可能丢失**，所以操作前会弹确认。
- **之后从 Dock 正常打开 Codex：** 端点会再次缺失，需要再点一次「重启并连接」。

如果窗口仍未连接，打开**「连接详情 → 打开日志文件位置」**。Packpier 会把加载器启动和 Codex 连接检查写入 `~/Library/Logs/Packpier/connection.log`。

## 第三方插件

插件市场支持导入本地 ZIP、调整顺序，并按用户保存。插件可以声明渲染入口（`packpier.entrypoints.renderer`），也可以额外声明 Node 后端（`packpier.entrypoints.node`）。

- 只含渲染入口的插件使用 Packpier 自带的窗口宿主，不需要 Node.js。
- 带 Node 后端的插件需要**系统 Node.js 22 或更高版本**。在「安装详情」审阅后点「允许当前版本」。Packpier 会为每个已启用且已授权的后端启动独立进程，停用后退出；插件内容变化后需要重新授权。
- 目前只有三个内置插件会注入 Codex 窗口；其他插件的效果会出现在市场列表里，但不会挂载。

## 数据与隐私

- 插件顺序、开关和插件设置保存在 `~/Library/Application Support/Packpier`。
- Prism 的配色保存在本机。自定义背景的内置图片来源会联网，收藏保存在 `~/Pictures/Packpier/收藏`。
- Packpier 不需要账号，也不会上传插件数据。

## 构建与测试

需要 Xcode、Node.js 22.13+、npm、Python 3、uv 和 Chrome。构建只在 JavaScript 工具链里使用 Node.js，并会校验下载的 Sparkle 框架。可用 `CHROME_BIN` 指定测试用的 Chrome。

```sh
make bootstrap
make check
open build/Packpier.app
./Scripts/build-dmg.sh
```

`make lint` 检查源码和分发文件，`make unit` 和 `make integration` 运行测试。内置插件源码位于 [Prism](Plugins/Prism)、[自定义背景](Plugins/CustomBackground) 和 [P-Sign](Resources/BundledPlugins/p-sign)。修改插件后执行 `python3 Scripts/plugin-archives.py` 同步市场归档。

## 发布与更新

Packpier 使用 Sparkle 2。维护者在构建后运行 `python3 Scripts/release.py`，它会生成更新 ZIP、用 macOS 钥匙串里的发布密钥签名 `appcast.xml`，并准备对应 GitHub Release 的资源。可用 `PACKPIER_SIGNING_ACCOUNT` 指定其他钥匙串条目。Apple Developer ID 签名、公证和最终发布是另外的步骤。

## 许可证

[MIT](LICENSE) · [第三方声明](THIRD_PARTY_NOTICES.md) · [插件开发 Skill](Resources/Skills/packpier-plugin-author/SKILL.md)