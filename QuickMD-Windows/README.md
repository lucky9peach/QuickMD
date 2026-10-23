# QuickMD for Windows 🪟

与 macOS 版**同思路、同布局、同渲染内核**的 Windows 版本：C# WinForms + WebView2（Edge 内核）。

- 秒开：启动即预热模板，打开文件只是一次 JS 调用
- 排版内核（`Resources/`）与 mac 版同源：`template.html` / `app.css` / `marked.min.js`
- 工具栏 / 状态条（`文件大小 · 字数 · 渲染ms`）/ 空态 / 快捷键一一对应（⌘ → Ctrl）
- 导出 PDF / 超长图 PNG（整页截图）/ 独立 HTML
- 文件外部修改自动重载、多窗口、拖放、主题（跟随/浅色/深色）、字号
- 「设为 .md 默认打开」写 HKCU 注册表，无需管理员权限

## 下载

[Releases](https://github.com/lucky9peach/QuickMD/releases) → `QuickMD.exe`，单文件，Win10/11 双击即用。
需要系统自带 Edge WebView2 Runtime（近几年 Win10/11 一般预装；若提示缺失去微软官网装一个即可）。

## 发版（Mac 上也能做）

```bash
git tag win-v1.0.0 && git push origin win-v1.0.0
```

GitHub Actions 会在 `windows-latest` 上编译，把 `QuickMD.exe` + portable zip 挂到 Release 下。
日常 push 到 main 只构建不发布，可去 Actions 页下载 artifact 试用。

## 本地编译（需 Windows + .NET 8 SDK）

```bash
dotnet publish QuickMD-Windows/QuickMD.csproj -c Release -o publish
```

## 改样式注意

`Resources/` 下三个文件是 mac 版 `QuickMD/Resources/` 的同步副本，改排版时两边一起改，保持一致。
