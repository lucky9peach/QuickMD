// QuickMD for Windows — 主窗口：菜单/工具栏/预览/状态条/导出（对标 mac 版 MDWindowController）
using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace QuickMD;

sealed record PendingDoc(string B64, string BaseHref, string Path, int Bytes, string Text, double ReadMs, int Words);

sealed class MainForm : Form
{
    readonly WebView2 _web = new();
    readonly ToolStripStatusLabel _status = new();
    readonly Panel _empty = new();
    string? _filePath;
    bool _webReady;
    PendingDoc? _pending;
    FileSystemWatcher? _watcher;
    DateTime _lastWatch = DateTime.MinValue;

    public string? FilePath => _filePath;

    public MainForm()
    {
        Text = "QuickMD";
        Size = new Size(1020, 760);
        MinimumSize = new Size(640, 480);
        StartPosition = FormStartPosition.CenterScreen;
        AllowDrop = true;

        var menu = BuildMenu();
        var toolbar = BuildToolbar();
        var strip = new StatusStrip { Dock = DockStyle.Bottom };
        _status.Text = "就绪 — 把 .md 文件拖进来，或按 Ctrl+O 打开";
        _status.Spring = true;
        _status.TextAlign = ContentAlignment.MiddleLeft;
        strip.Items.Add(_status);

        _web.Dock = DockStyle.Fill;
        _empty.Dock = DockStyle.Fill;
        BuildEmptyView();

        Controls.Add(_web);
        Controls.Add(_empty);
        Controls.Add(strip);
        Controls.Add(toolbar);
        Controls.Add(menu);
        // 明确 z-order：边缘栏在前、填充控件在后（WinForms 按此顺序停靠）
        Controls.SetChildIndex(menu, 0);
        Controls.SetChildIndex(toolbar, 1);
        Controls.SetChildIndex(strip, 2);
        Controls.SetChildIndex(_empty, 3);
        Controls.SetChildIndex(_web, 4);

        DragEnter += (_, e) =>
        {
            if (e.Data?.GetDataPresent(DataFormats.FileDrop) == true)
                e.Effect = DragDropEffects.Copy;
        };
        DragDrop += (_, e) =>
        {
            if (e.Data?.GetData(DataFormats.FileDrop) is not string[] files || files.Length == 0) return;
            List<string> mds = files.Where(File.Exists).ToList();
            if (mds.Count == 0) return;
            if (_filePath == null)
            {
                OpenFile(mds[0]);
                if (mds.Count > 1) Program.OpenFiles(mds.Skip(1));
            }
            else Program.OpenFiles(mds);
        };
        FormClosed += (_, _) => StopWatching();

        InitWeb(); // 预热：立即加载空模板，后续渲染只是 JS 调用
    }

    // ---- 菜单 ----
    MenuStrip BuildMenu()
    {
        var menu = new MenuStrip { Dock = DockStyle.Top };

        var file = new ToolStripMenuItem("文件(&F)");
        file.DropDownItems.Add(new ToolStripMenuItem("新建窗口", null, (_, _) => Program.NewWindow(), Keys.Control | Keys.N));
        file.DropDownItems.Add(new ToolStripMenuItem("打开(&O)…", null, (_, _) => OpenDialog(), Keys.Control | Keys.O));
        file.DropDownItems.Add(new ToolStripMenuItem("重新载入", null, (_, _) => Reload(), Keys.Control | Keys.R));
        file.DropDownItems.Add(new ToolStripSeparator());
        file.DropDownItems.Add(new ToolStripMenuItem("导出 PDF…", null, (_, _) => ExportPdf(), Keys.Control | Keys.E));
        file.DropDownItems.Add(new ToolStripMenuItem("导出长图 PNG…", null, (_, _) => ExportPng(), Keys.Control | Keys.Shift | Keys.E));
        file.DropDownItems.Add(new ToolStripMenuItem("导出 HTML…", null, (_, _) => ExportHtml(), Keys.Control | Keys.H));
        file.DropDownItems.Add(new ToolStripSeparator());
        file.DropDownItems.Add(new ToolStripMenuItem("设为 .md 默认打开", null, (_, _) => SetDefault()));
        file.DropDownItems.Add(new ToolStripSeparator());
        file.DropDownItems.Add(new ToolStripMenuItem("关闭窗口", null, (_, _) => Close(), Keys.Control | Keys.W));
        file.DropDownItems.Add(new ToolStripMenuItem("退出", null, (_, _) => Application.Exit(), Keys.Alt | Keys.F4));

        var view = new ToolStripMenuItem("显示(&V)");
        view.DropDownItems.Add(new ToolStripMenuItem("放大字号", null, (_, _) => SetFont(Prefs.FontSize + 1), Keys.Control | Keys.Oemplus));
        view.DropDownItems.Add(new ToolStripMenuItem("缩小字号", null, (_, _) => SetFont(Prefs.FontSize - 1), Keys.Control | Keys.OemMinus));
        view.DropDownItems.Add(new ToolStripMenuItem("默认字号", null, (_, _) => SetFont(16), Keys.Control | Keys.D0));
        view.DropDownItems.Add(new ToolStripSeparator());
        view.DropDownItems.Add(new ToolStripMenuItem("切换主题", null, (_, _) => ToggleTheme(), Keys.Control | Keys.T));

        var help = new ToolStripMenuItem("帮助(&H)");
        help.DropDownItems.Add(new ToolStripMenuItem("关于 QuickMD", null, (_, _) =>
            MessageBox.Show(this, "QuickMD for Windows\n秒开的 Markdown 阅读器\n\nWinForms + WebView2，渲染内核与 macOS 版一致。", "关于 QuickMD")));

        menu.Items.Add(file);
        menu.Items.Add(view);
        menu.Items.Add(help);
        return menu;
    }

    // ---- 工具栏（对标 mac 版 toolbar 图标顺序） ----
    ToolStrip BuildToolbar()
    {
        var tb = new ToolStrip { Dock = DockStyle.Top, GripStyle = ToolStripGripStyle.Hidden };
        ToolStripButton Btn(string text, string tip, Action onClick)
        {
            var b = new ToolStripButton(text) { ToolTipText = tip, DisplayStyle = ToolStripItemDisplayStyle.Text };
            b.Click += (_, _) => onClick();
            return b;
        }
        tb.Items.Add(Btn("📂 打开", "打开 Markdown 文件 (Ctrl+O)", OpenDialog));
        tb.Items.Add(Btn("⟳ 重载", "重新载入 (Ctrl+R)", Reload));
        tb.Items.Add(new ToolStripSeparator());
        tb.Items.Add(Btn("⬇ PDF", "导出 PDF (Ctrl+E)", ExportPdf));
        tb.Items.Add(Btn("🖼 长图", "导出超长图 PNG (Ctrl+Shift+E)", ExportPng));
        tb.Items.Add(Btn("🌐 HTML", "导出 HTML (Ctrl+H)", ExportHtml));
        tb.Items.Add(new ToolStripSeparator());
        tb.Items.Add(Btn("A−", "缩小字号 (Ctrl+-)", () => SetFont(Prefs.FontSize - 1)));
        tb.Items.Add(Btn("A＋", "放大字号 (Ctrl++)", () => SetFont(Prefs.FontSize + 1)));
        tb.Items.Add(Btn("◐ 主题", "切换主题：跟随/浅色/深色 (Ctrl+T)", ToggleTheme));
        return tb;
    }

    // ---- 空态 ----
    void BuildEmptyView()
    {
        _empty.BackColor = SystemColors.Window;
        var grid = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 3, RowCount = 3 };
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        grid.RowStyles.Add(new RowStyle(SizeType.Percent, 50));
        grid.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        grid.RowStyles.Add(new RowStyle(SizeType.Percent, 50));

        var box = new TableLayoutPanel { AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, ColumnCount = 1, Anchor = AnchorStyles.None };
        box.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        var icon = new Label { Text = "📄", Font = new Font("Segoe UI Emoji", 48), AutoSize = true, Anchor = AnchorStyles.None, TextAlign = ContentAlignment.MiddleCenter };
        var t1 = new Label { Text = "QuickMD 秒开预览", Font = new Font("Microsoft YaHei UI", 18, FontStyle.Bold), AutoSize = true, Anchor = AnchorStyles.None };
        var t2 = new Label { Text = "把 Markdown 文件拖到这里，或点击下方按钮打开\n支持 .md / .markdown / .mdown / .mkd / .txt", Font = new Font("Microsoft YaHei UI", 10), ForeColor = SystemColors.GrayText, AutoSize = true, Anchor = AnchorStyles.None, TextAlign = ContentAlignment.MiddleCenter };
        var btn = new Button { Text = "打开文件…", AutoSize = true, Anchor = AnchorStyles.None, Margin = new Padding(0, 14, 0, 0) };
        btn.Click += (_, _) => OpenDialog();
        box.Controls.Add(icon);
        box.Controls.Add(t1);
        box.Controls.Add(t2);
        box.Controls.Add(btn);
        grid.Controls.Add(box, 1, 1);
        _empty.Controls.Add(grid);
    }

    // ---- WebView2 预热 ----
    async void InitWeb()
    {
        try
        {
            string udf = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "QuickMD", "WebView2");
            Directory.CreateDirectory(udf);
            var env = await CoreWebView2Environment.CreateAsync(browserExecutableFolder: null, userDataFolder: udf);
            await _web.EnsureCoreWebView2Async(env);
            var core = _web.CoreWebView2;
            if (core == null) throw new InvalidOperationException("CoreWebView2 创建失败");
            core.Settings.IsStatusBarEnabled = false;
            // 外链用系统浏览器打开
            core.NewWindowRequested += (_, e) =>
            {
                try { Process.Start(new ProcessStartInfo(e.Uri) { UseShellExecute = true }); } catch { }
                e.Handled = true;
            };
            core.NavigationCompleted += (_, e) =>
            {
                if (!e.IsSuccess) return;
                _webReady = true;
                ApplyPrefs();
                if (_pending is { } p) { _pending = null; RenderPending(p); }
            };
            core.NavigateToString(TemplateStore.Shared.HtmlShell);
        }
        catch (Exception ex)
        {
            _status.Text = "WebView2 初始化失败（需安装 Edge WebView2 Runtime）：" + ex.Message;
        }
    }

    void ApplyPrefs()
    {
        if (!_webReady) return;
        _ = _web.ExecuteScriptAsync($"window.__setTheme && __setTheme('{Prefs.Theme}')");
        _ = _web.ExecuteScriptAsync($"window.__setFontSize && __setFontSize({Prefs.FontSize})");
    }

    // ---- 打开 / 渲染 ----
    public void OpenFile(string path) { _ = OpenFileAsync(path); }

    async Task OpenFileAsync(string path)
    {
        var t0 = DateTime.UtcNow;
        var read = await Task.Run(() => Utils.ReadTextFile(path));
        if (read == null) { Toast("无法读取文件：" + path); return; }
        var (text, bytes) = read.Value;
        string b64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(text));
        string baseHref = "";
        try { baseHref = new Uri(Path.GetDirectoryName(Path.GetFullPath(path)) + Path.DirectorySeparatorChar).AbsoluteUri.Replace("'", "%27"); }
        catch { }
        int words = Utils.CountWords(text);
        double readMs = (DateTime.UtcNow - t0).TotalMilliseconds;

        _filePath = path;
        _empty.Visible = false;
        Text = Path.GetFileName(path) + " — QuickMD";
        StartWatching(path);
        var doc = new PendingDoc(b64, baseHref, path, bytes, text, readMs, words);
        if (_webReady) RenderPending(doc);
        else _pending = doc;
    }

    async void RenderPending(PendingDoc p)
    {
        var t0 = DateTime.UtcNow;
        try
        {
            // base64 只含 [A-Za-z0-9+/=]，可安全拼入 JS 单引号
            string result = await _web.ExecuteScriptAsync($"window.__renderMD('{p.B64}','{p.BaseHref}')");
            double jsMs = -1;
            if (double.TryParse(result, NumberStyles.Any, CultureInfo.InvariantCulture, out var v)) jsMs = v;
            double totalMs = (DateTime.UtcNow - t0).TotalMilliseconds + p.ReadMs;
            double show = jsMs >= 0 ? jsMs : totalMs;
            _status.Text = $"{Utils.FormatBytes(p.Bytes)} · {p.Words} 字 · 渲染 {show:0} ms";
        }
        catch (Exception ex) { _status.Text = "渲染失败：" + ex.Message; }
    }

    // ---- 文件监听（对标 mac 版 DispatchSource，外部修改自动重载） ----
    void StartWatching(string path)
    {
        StopWatching();
        try
        {
            string? dir = Path.GetDirectoryName(path);
            string name = Path.GetFileName(path);
            if (dir == null) return;
            _watcher = new FileSystemWatcher(dir, name)
            {
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.FileName,
                EnableRaisingEvents = true,
            };
            _watcher.Changed += (_, _) => DebouncedReload(path);
            _watcher.Renamed += (_, _) => DebouncedReload(path);
        }
        catch { }
    }

    void DebouncedReload(string path)
    {
        var now = DateTime.UtcNow;
        if ((now - _lastWatch).TotalMilliseconds < 400) return;
        _lastWatch = now;
        BeginInvoke(new Action(() =>
        {
            if (File.Exists(path) && path == _filePath) OpenFile(path);
        }));
    }

    void StopWatching()
    {
        try { _watcher?.Dispose(); } catch { }
        _watcher = null;
    }

    void Toast(string msg)
    {
        _status.Text = msg;
        MessageBox.Show(this, msg, "QuickMD", MessageBoxButtons.OK, MessageBoxIcon.Warning);
    }

    // ---- 菜单/工具栏动作 ----
    void OpenDialog()
    {
        using var dlg = new OpenFileDialog
        {
            Filter = "Markdown 文件|*.md;*.markdown;*.mdown;*.mkd;*.mkdn;*.mdtext;*.rmd;*.txt;*.text|所有文件|*.*",
            Multiselect = true,
        };
        if (dlg.ShowDialog(this) != DialogResult.OK) return;
        if (_filePath == null)
        {
            OpenFile(dlg.FileNames[0]);
            if (dlg.FileNames.Length > 1) Program.OpenFiles(dlg.FileNames.Skip(1));
        }
        else Program.OpenFiles(dlg.FileNames);
    }

    void Reload()
    {
        if (_filePath != null) OpenFile(_filePath);
    }

    void SetFont(int px)
    {
        Prefs.FontSize = px; // 内部 clamp + 持久化
        if (_webReady) _ = _web.ExecuteScriptAsync($"window.__setFontSize && __setFontSize({Prefs.FontSize})");
    }

    void ToggleTheme()
    {
        string[] order = new[] { "auto", "light", "dark" };
        string[] names = new[] { "跟随系统", "浅色", "深色" };
        int cur = Array.IndexOf(order, Prefs.Theme);
        if (cur < 0) cur = 0;
        int next = (cur + 1) % order.Length;
        Prefs.Theme = order[next];
        if (_webReady) _ = _web.ExecuteScriptAsync($"window.__setTheme && __setTheme('{Prefs.Theme}')");
        _status.Text = "主题：" + names[next];
    }

    void SetDefault()
    {
        string r = DefaultApp.TryRegister();
        if (r == "ok")
            MessageBox.Show(this, "已注册 QuickMD 打开方式。\n\n若双击仍用旧应用打开：右键任一 .md 文件 → 打开方式 → 选择 QuickMD 并勾选“始终使用此应用”。", "设为默认", MessageBoxButtons.OK, MessageBoxIcon.Information);
        else
            MessageBox.Show(this, "注册失败：" + r, "设为默认", MessageBoxButtons.OK, MessageBoxIcon.Warning);
    }

    // ---- 导出 ----
    string DefaultExportName(string ext)
    {
        string baseName = "QuickMD导出";
        if (_filePath != null) baseName = Path.GetFileNameWithoutExtension(_filePath) ?? baseName;
        return baseName + "." + ext;
    }

    async void ExportPdf()
    {
        if (_filePath == null) { Toast("先打开一个 Markdown 文件再导出"); return; }
        var core = _web.CoreWebView2;
        if (core == null) { Toast("页面尚未就绪，稍候再试"); return; }
        using var dlg = new SaveFileDialog { FileName = DefaultExportName("pdf"), Filter = "PDF 文件|*.pdf" };
        if (dlg.ShowDialog(this) != DialogResult.OK) return;
        try
        {
            _status.Text = "正在生成 PDF…";
            var settings = core.Environment.CreatePrintSettings();
            settings.Orientation = CoreWebView2PrintOrientation.Portrait;
            settings.PageWidth = 8.27;   // A4（英寸）
            settings.PageHeight = 11.69;
            settings.MarginTop = 0.4;    // 窄边距 ~10mm
            settings.MarginBottom = 0.4;
            settings.MarginLeft = 0.4;
            settings.MarginRight = 0.4;
            settings.ShouldPrintBackgrounds = true;
            settings.ShouldPrintHeaderAndFooter = false;
            await core.PrintToPdfAsync(dlg.FileName, settings);
            long len = new FileInfo(dlg.FileName).Length;
            _status.Text = $"已导出 PDF：{Path.GetFileName(dlg.FileName)} ({Utils.FormatBytes((int)Math.Min(len, int.MaxValue))})";
        }
        catch (Exception ex) { Toast("PDF 生成失败：" + ex.Message); }
    }

    async void ExportHtml()
    {
        if (_filePath == null) { Toast("先打开一个 Markdown 文件再导出"); return; }
        using var dlg = new SaveFileDialog { FileName = DefaultExportName("html"), Filter = "HTML 文件|*.html" };
        if (dlg.ShowDialog(this) != DialogResult.OK) return;
        try
        {
            string result = await _web.ExecuteScriptAsync("window.__contentHTML()");
            string inner = JsonSerializer.Deserialize<string>(result) ?? "";
            string title = _filePath != null ? (Path.GetFileNameWithoutExtension(_filePath) ?? "QuickMD") : "QuickMD";
            string doc = $"<!DOCTYPE html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>{WebUtility.HtmlEncode(title)}</title><style>{TemplateStore.Shared.Css}</style></head><body><article id=\"content\">{inner}</article></body></html>";
            await File.WriteAllTextAsync(dlg.FileName, doc, Encoding.UTF8);
            _status.Text = "已导出 HTML：" + Path.GetFileName(dlg.FileName);
        }
        catch (Exception ex) { Toast("HTML 导出失败：" + ex.Message); }
    }

    async void ExportPng()
    {
        if (_filePath == null) { Toast("先打开一个 Markdown 文件再导出"); return; }
        var core = _web.CoreWebView2;
        if (core == null) { Toast("页面尚未就绪，稍候再试"); return; }
        using var dlg = new SaveFileDialog { FileName = DefaultExportName("png"), Filter = "PNG 图片|*.png" };
        if (dlg.ShowDialog(this) != DialogResult.OK) return;
        try
        {
            _status.Text = "正在生成长图…";
            string hResult = await _web.ExecuteScriptAsync("window.__contentHeight()");
            int h = 1200;
            if (double.TryParse(hResult, NumberStyles.Any, CultureInfo.InvariantCulture, out var hv)) h = (int)hv;
            h = Math.Clamp(h, 200, 30000);
            int w = Math.Max(200, _web.ClientSize.Width);
            byte[] png;
            try
            {
                // 整页截图（含可视区外），超长时降采样防爆显存
                int scale = h > 12000 ? 1 : 2;
                string param = $"{{\"format\":\"png\",\"captureBeyondViewport\":true,\"fromSurface\":true,\"clip\":{{\"x\":0,\"y\":0,\"width\":{w},\"height\":{h},\"scale\":{scale}}}}}";
                string res = await core.CallDevToolsProtocolMethodAsync("Page.captureScreenshot", param);
                using var doc = JsonDocument.Parse(res);
                png = Convert.FromBase64String(doc.RootElement.GetProperty("data").GetString() ?? "");
                if (png.Length == 0) throw new InvalidOperationException("截图数据为空");
            }
            catch
            {
                // 兜底：当前可视区截图
                using var ms = new MemoryStream();
                await core.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, ms);
                png = ms.ToArray();
            }
            await File.WriteAllBytesAsync(dlg.FileName, png);
            _status.Text = $"已导出长图：{Path.GetFileName(dlg.FileName)} ({Utils.FormatBytes(png.Length)})";
        }
        catch (Exception ex) { Toast("长图生成失败：" + ex.Message); }
    }
}
