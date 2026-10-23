# QuickMD ⚡

**A blazing-fast native Markdown viewer for macOS — 秒开的 macOS Markdown 阅读器。**

~200KB pure Swift binary. Double-click any `.md` file and it renders in ~10–20ms.
No Electron, no bloat. Export to PDF / ultra-long PNG / standalone HTML.

[中文说明](#中文说明) · [Features](#features) · [Build](#build--install) · [License](#license)

> 🪟 **Windows 版**：同思路的 Windows 版本（WinForms + WebView2）已就绪，单文件 `QuickMD.exe` 双击即用 → [Releases 下载](https://github.com/lucky9peach/QuickMD/releases)。

## Features

- **Instant open** — pre-warmed render engine; opening a file is a single JS call (~10–20ms)
- **Clean typography** — 16px body, 1.8 line-height, auto spacing for headings/paragraphs/lists
- **Full GFM** — tables, code blocks, task lists, blockquotes (powered by [marked](https://github.com/markedjs/marked))
- **Export** — A4 paginated PDF with narrow margins (`⌘E`), ultra-long PNG with auto-stitching (`⇧⌘E`), standalone HTML (`⌘H`)
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
QuickMD/                          # macOS 版（Swift + WKWebView）
├── Sources/QuickMD.swift   # The entire app — one file (~650 lines)
├── Resources/
│   ├── template.html       # Render shell + JS bridge
│   ├── app.css             # Typography & themes
│   └── marked.min.js       # Markdown parser (MIT, by marked.js)
├── Info.plist              # Bundle + .md document types
├── build.sh                # Compile → bundle → sign → install
├── SetDefault.swift        # Set default opener via LaunchServices
└── makeicon.swift          # Generates AppIcon.icns
QuickMD-Windows/                  # Windows 版（C# WinForms + WebView2）
├── Program.cs              # 入口 + 多窗口管理
├── MainForm.cs             # 主窗口：工具栏/预览/状态条/导出
├── Support.cs              # 模板缓存/偏好/编码/默认打开注册
├── Resources/              # 与 mac 版同源的渲染内核
└── QuickMD.csproj          # .NET 8 单文件 exe 工程
.github/workflows/windows.yml    # 云端编译：push 构建，win-v* 标签自动发 Release
Examples/排版测试.md         # Sample file to try rendering
```

## Windows 版 🪟

同思路、同布局的 Windows 版本：C# WinForms + WebView2（Edge 内核），渲染内核与 mac 版同源，功能对齐（秒开、导出 PDF/长图/HTML、自动重载、主题字号、设为默认打开）。

**下载**：[Releases](https://github.com/lucky9peach/QuickMD/releases) → `QuickMD.exe`（单文件，Win10/11 双击即用，需系统自带 WebView2 Runtime，新系统一般都有）。

**云端构建**（Mac 上也可做 Windows 发版）：

```bash
git tag win-v1.0.0 && git push origin win-v1.0.0
```

GitHub Actions 会在 `windows-latest` 上编译并把 exe / portable zip 挂到 Release 下。日常 push 到 main 只构建不发布，可在 Actions 页下载 artifact 试用。

本地有 Windows 机器时也可手动编译：`dotnet publish QuickMD-Windows/QuickMD.csproj -c Release -o publish`。

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
