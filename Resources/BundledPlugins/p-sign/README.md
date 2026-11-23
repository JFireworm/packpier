# P-Sign

P-Sign 在 Codex 左下角显示 Packpier 的 P 标志。绿点表示 P-Sign 已在当前窗口加载。指针移到 P 上，或用 Tab 聚焦 P，即可展开快捷操作。Tab 可移动到按钮，Enter 或空格执行，Esc 收起面板。

## 给自己的插件添加悬停操作

从 P-Sign 1.3.0 起，内置和本地安装的插件都可以使用下面的 v1 接口。每个操作对应插件自己维护的一个 HTML 按钮。P-Sign 在当前窗口展示它的图标和提示，将点击交给原按钮处理。整个示例只需要 Codex 插件的 renderer 入口。

下面的 `activate` 可以直接放进插件的 `src/index.js`。它在 P 的菜单中添加「切换笔记」按钮，点击会显示或收起一张本地便签。

```js
export function activate({ root, onCleanup }) {
  const note = document.createElement("aside");
  note.textContent = "我的便签";
  note.hidden = true;
  note.style.cssText = "position:fixed;right:16px;bottom:24px;padding:10px;background:#26405b;color:white;border-radius:8px";

  const action = document.createElement("button");
  action.type = "button";
  action.hidden = true;
  action.dataset.packpierPSignAction = "my-notes/toggle";
  action.setAttribute("aria-label", "切换笔记");
  action.title = "显示或收起我的便签";
  action.dataset.packpierPSignPath = "M5 3h10l4 4v14H5z M9 11h6 M9 15h6";
  action.addEventListener("click", () => { note.hidden = !note.hidden; });

  const notify = () => document.dispatchEvent(new Event("packpier:p-sign:actions-changed:v1"));
  root.append(note, action);
  notify();
  onCleanup(() => {
    action.remove();
    note.remove();
    notify();
  });
}
```

### v1 约定

| 按钮字段 | 用途 |
| --- | --- |
| `data-packpier-p-sign-action` | 必填，格式为 `插件ID/操作ID`，例如 `my-notes/toggle`。两段均以小写字母或数字开头，可含小写字母、数字、点、下划线和短横线。一个插件可以提供多个不同 ID 的按钮。同一窗口遇到重复 ID 时取文档顺序中的第一个有效按钮。 |
| `aria-label` | 必填，简短的操作名称。插件负责按当前语言设置，用于辅助功能和默认悬停提示。 |
| `title` | 可选，悬停说明，也可说明操作暂不可用的原因。 |
| `data-packpier-p-sign-path` | 可选，一个 24 × 24 坐标系里的 SVG 描边路径 `d`，自动跟随主题色，缺省使用加号。 |
| `disabled` 或 `aria-disabled="true"` | 暂停操作并保留其入口。恢复时清除禁用状态。 |

将按钮挂在插件的 `root` 下，放在当前文档可查询的普通 DOM 中。可用 `hidden` 避免按钮占用原界面的位置。P-Sign 展开时读取现有按钮，因此插件先后加载或单独重载均可。展开期间增删按钮、切换语言或修改禁用状态后，向 `document` 派发一次 `packpier:p-sign:actions-changed:v1` 即可立即更新。停用插件时先移除自己的按钮，再派发事件。

### 在 Packpier 验证

1. 在插件市场选择 Codex，安装并启用自己的插件，确认 P-Sign 版本至少为 1.3.0。
2. 悬停于左下角的 P，移动到新图标查看提示，点击核对实际效果。
3. 停用插件，入口应消失。再次启用，入口应只出现一次。P-Sign 随附的背景快捷操作可继续使用。
