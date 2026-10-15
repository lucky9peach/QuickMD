# QuickMD ⚡

**A blazing-fast native Markdown viewer for macOS — 秒开的 macOS Markdown 阅读器。**

~200KB pure Swift binary. Double-click any `.md` file and it renders in ~10–20ms.
No Electron, no bloat. Export to PDF / ultra-long PNG / standalone HTML.

[中文说明](#中文说明) · [Features](#features) · [Build](#build--install) · [License](#license)

## Features

- **Instant open** — pre-warmed render engine; opening a file is a single JS call (~10–20ms)
- **Clean typography** — 16px body, 1.8 line-height, auto spacing for headings/paragraphs/lists
- **Full GFM** — tables, code blocks, task lists, blockquotes (powered by [marked](https://github.com/markedjs/marked))
- **Export** — paginated PDF (`⌘E`), ultra-long PNG with auto-stitching (`⇧⌘E`), standalone HTML (`⌘H`)
- **Live reload** — auto re-renders when the file changes on disk
- **Multi-window** — each file in its own window; drag & drop supported
- **Themes** — follows system, or force light/dark (`⌘T`); adjustable font size (`⌘+`/`⌘-`/`⌘0`)
- **Set as default** — one command to make QuickMD the default `.md` opener

## Requirements

- macOS 12.0+
- Swift toolchain: Xcode **or** Command Line Tools (`xcode-select --install`)

## Build & Install

```bash
git clone https://github.com/lucky9peach/QuickMD.git
cd QuickMD/QuickMD
./build.sh
```

This compiles (`swiftc -O`), bundles `QuickMD.app`, and installs it to `/Applications`.

> First launch on other machines: right-click `QuickMD.app` → **Open** (ad-hoc signature, one-time Gatekeeper bypass).

### Set as default Markdown opener

```bash
cd QuickMD
swiftc -O SetDefault.swift -o build/SetDefault && ./build/SetDefault
```

To revert: right-click any `.md` → Get Info → Open with → choose your app → **Change All**.

## Usage

| Action | How |
|---|---|
| Open | Double-click `.md` / drag into window / `⌘O` |
| Reload | `⌘R` (also auto-reloads on external change) |
| Export PDF / PNG / HTML | Toolbar or `⌘E` / `⇧⌘E` / `⌘H` |
| Font size | `⌘+` / `⌘-` / `⌘0` |
| Theme (auto/light/dark) | `⌘T` |

The status bar shows `file size · word count · render ms` after each open.

## Project structure

```
QuickMD/
├── Sources/QuickMD.swift   # The entire app — one file (~650 lines)
├── Resources/
│   ├── template.html       # Render shell + JS bridge
│   ├── app.css             # Typography & themes
│   └── marked.min.js       # Markdown parser (MIT, by marked.js)
├── Info.plist              # Bundle + .md document types
├── build.sh                # Compile → bundle → sign → install
├── SetDefault.swift        # Set default opener via LaunchServices
└── makeicon.swift          # Generates AppIcon.icns
Examples/排版测试.md         # Sample file to try rendering
```

## Credits

- Markdown parsing: [marked](https://github.com/markedjs/marked) (MIT License)

## Contributing

Issues and PRs welcome. Keep it fast — every millisecond counts. ⚡

## License

[MIT](LICENSE) © 2026 lucky9peach

---

## 中文说明

QuickMD 是一个为「快」而生的 macOS Markdown 阅读器：原生 Swift 单文件打造，程序本体仅约 200KB，无 Electron、无臃肿依赖。双击 `.md` 文件约 10–20ms 完成渲染，底部状态条实时显示字数与渲染耗时。

**构建安装**：参考上面 [Build & Install](#build--install)，只需装有 Xcode 或 Command Line Tools，运行 `./build.sh` 即可编译安装到 `/Applications`。

**设为默认打开**：运行 `SetDefault.swift`（见上），之后双击所有 Markdown 文件都会用 QuickMD 秒开。

欢迎 Star ⭐、提 Issue 和 PR！
