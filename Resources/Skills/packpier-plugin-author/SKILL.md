---
name: packpier-plugin-author
description: 为 Packpier 0.1.29 制作和验证 Codex v3 ZIP，或从源码开发与测试内置窗口效果。
---

# 为 Packpier 开发插件包

## 0.1.29 的能力边界

Packpier 可打包和导入 Codex v3 ZIP。在插件市场可查看安装记录、调整顺序、启停插件，并审阅 Node 权限。
Codex 窗口效果只来自随 App 编译的 P-Sign、Prism 和自定义背景。第三方 ZIP 的 renderer 暂不挂载。

## 最小 Codex v3 ZIP

在独立目录创建以下两份文件。导入此 ZIP 用于验证结构与清单。示例节点只有在 renderer 被宿主挂载时才会创建，因此导入后 Codex 窗口不会显示示例内容。

`package.json`

```json
{
  "name": "packpier-greeting",
  "version": "1.0.0",
  "description": "用于验证 Packpier 插件包导入的示例",
  "type": "module",
  "packpier": {
    "apiVersion": 3,
    "entrypoints": { "renderer": "src/index.js" }
  }
}
```

`src/index.js`

```js
export function activate({ root, onCleanup }) {
  const label = document.createElement("div");
  label.textContent = "Packpier 示例";
  root.append(label);
  onCleanup(() => label.remove());
}
```

## 开发与验证内置效果

在仓库中修改对应内置插件源码，由 `Loader/Renderer/index.js` 引入并编译进 App。新增监听器、定时器或节点时，在 `onCleanup` 中清理。
首次构建先执行 `make bootstrap`。用 `make integration` 构建 App 并运行集成测试，验证窗口挂载、交互和退出清理。

## 第三方 Node 后端

使用系统 Node.js 22+。在清单声明 `packpier.entrypoints.node` 和 `packpier.permissions.node.reason`，在权限说明中列出读写数据、联网和启动进程的用途。
入口导出 `activate({ dataDirectory, rpc })`，可返回清理函数。`rpc.handle(method, handler)` 注册方法，`rpc.emit(name, payload)` 发送事件。
用户在安装详情审阅并授权后，启用的后端通过私有 stdio 会话运行。包内容变更后需重新授权。0.1.29 的第三方后端要等 renderer 挂载能力落地后才有窗口侧调用方。

## P-Sign v1 与设置页

这两类 UI 接口现供内置效果使用。第三方 ZIP 需要等 renderer 挂载能力落地后才能接入。
- P-Sign v1 使用插件 `root` 下的隐藏按钮。设置 `data-packpier-p-sign-action="插件ID/操作ID"` 和本地化 `aria-label`，绑定点击行为。增删按钮或改动属性后向 `document` 派发 `packpier:p-sign:actions-changed:v1`，清理时先移除按钮再派发。
- 设置页参考内置自定义背景的 `ui.settingsSections.register({ id, mount })`。用 `mount(container)` 挂载面板，并在插件清理时调用注册句柄的 `unregister()`。

## 打包与验收

1. 在包根目录执行 `zip -r ../packpier-greeting.zip package.json src`。清单可位于 ZIP 根或单个一级目录。随包列入实际所需的资源与锁文件，排除 `node_modules`、账号数据和密钥。
2. 在「插件市场 → Codex → 安装插件包」导入。核对 ID、版本、安装记录和排序。停用后重新启用，核对状态保存。带 Node 后端的包还需核对权限说明、授权状态及内容变更后重新授权的提示。

[Packpier 仓库与源码](https://github.com/JFireworm/packpier) · [单插件更新的后续设计](https://github.com/JFireworm/packpier/blob/main/docs/plugin-updates.md)
