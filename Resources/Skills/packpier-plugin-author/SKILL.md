---
name: packpier-plugin-author
description: 为 Packpier 当前已接入的应用开发、打包和验证本地插件包，适用于通过 Codex 适配器交付Codex v3 ZIP。
---

# 为 Packpier 开发插件包

先确认目标应用与可观察的效果。Packpier 的「插件市场 → 目标应用」决定使用哪套适配器协议。当前已实现的是 Codex，使用 Packpier 内置的 Codex v3 适配器。其他应用只有在对应适配器存在后才可交付。沿用已有包的 ID 和目录，在独立工作目录准备新包。

## 最小可运行的 Codex 包

把以下两段分别存入包目录。示例只在启用时在窗口右下角显示一个提示，可用于验证 ZIP 结构与导入。当前发布版的窗口加载器只运行随 App 编译的三个内置插件。实际交付时替换为用户要求的功能，并使用自己的包 ID。

`package.json`

```json
{
  "name": "packpier-greeting",
  "version": "1.0.0",
  "description": "在 Codex 窗口右下角显示已启用的提示",
  "type": "module",
  "dependencies": {},
  "packpier": {
    "apiVersion": 3,
    "entrypoints": { "renderer": "src/index.js" },
    "packageDependencies": {}
  }
}
```

`src/index.js`

```js
export function activate({ root, onCleanup }) {
  const badge = document.createElement("div");
  badge.textContent = "Packpier ✓";
  badge.style.cssText = "position:fixed;right:16px;bottom:16px;padding:5px 10px;border-radius:8px;background:#243660;color:white;pointer-events:none";
  root.append(badge);
  onCleanup(() => badge.remove());
}
```

使用包自己的 root。为新增监听器、定时器、观察器和对宿主节点的改动注册清理。声明实际使用的跨包依赖，加载器会优先满足依赖顺序，用户可以在 Packpier 内拖动独立包排序。npm 依赖与插件依赖分别声明，使用 npm 依赖时随包交付锁文件。

## 接入 P-Sign 悬停面板

若插件需要在 Codex 左下角 P 的悬停菜单中提供快捷操作，使用 P-Sign 1.3.0 起的 v1 接口。在 renderer 的 `activate` 中，为每个操作创建 `type="button"` 的隐藏按钮，挂在自己的 `root` 下。设 `data-packpier-p-sign-action="插件ID/操作ID"` 和本地化的 `aria-label`，把业务逻辑绑定到该按钮的 click。可用 `title` 提供提示、`disabled` 控制可用性、`data-packpier-p-sign-path` 提供 24 × 24 SVG 描边路径。接入可作为可选增强，支持任意加载顺序。

按钮挂载、属性改变后，向 `document` 派发 `new Event("packpier:p-sign:actions-changed:v1")`。在 `onCleanup` 中先移除按钮再派发同一事件。验证展开、点击、禁用、停用后消失、再次启用只出现一次。完整的可运行示例在 P-Sign 源码 ZIP 的 `README.md`，仓库内位置为 `Resources/BundledPlugins/p-sign/README.md`。

## 打包和验收

1. 在包目录写 README，说明目标、可见效果、所读写的数据、网络和本机权限。使用本地 ZIP 交付时无需 GitHub 地址。
2. 在包根目录运行 `zip -r ../packpier-greeting.zip package.json src README.md`。清单可位于 ZIP 根或单个一级目录。把所需资源和锁文件一起放入，排除 node_modules、账户数据和密钥。
3. 打开 Packpier → 插件市场 → 选择 Codex → 安装本地插件包。核对 ID、版本和权限说明，添加后核对插件记录。内置插件的窗口效果通过构建 Packpier 并运行集成测试验证。同名同版本会复用现有副本。验证新源码时使用隔离的加载器数据目录。
4. 停用、再次启用，核对界面随开关消失、显示且只出现一次。分别记录编译结果、实际运行平台和看到的效果。

标题栏与设置页使用适配器提供的 UI 接口。需要 Node 时，在清单中声明 `packpier.entrypoints.node` 和 `packpier.permissions.node.reason`，列明读写的数据、联网用途和启动的进程。导入后，在 Packpier 中审阅当前版本的权限。

[Packpier 项目与源码](https://github.com/JFireworm/packpier)
