// QuickMD — 秒开 Markdown 阅读器
// 单文件 AppKit + WKWebView，启动快、渲染快、导出快
import Cocoa
import WebKit

// MARK: - 全局：模板缓存（只读一次磁盘）
final class TemplateStore {
    static let shared = TemplateStore()
    let htmlShell: String
    let css: String
    private init() {
        let fm = FileManager.default
        // Resources 定位：优先 Bundle，兜底可执行文件旁 / 开发目录
        var resDir: URL? = Bundle.main.resourceURL
        if resDir == nil || !fm.fileExists(atPath: resDir!.appendingPathComponent("template.html").path) {
            let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            let cands = [exeDir.appendingPathComponent("../Resources"),
                         exeDir.appendingPathComponent("../../Resources")]
            for c in cands {
                if fm.fileExists(atPath: c.appendingPathComponent("template.html").path) { resDir = c.standardized; break }
            }
        }
        func read(_ name: String) -> String {
            guard let d = resDir else { return "" }
            return (try? String(contentsOf: d.appendingPathComponent(name), encoding: .utf8)) ?? ""
        }
        let tpl = read("template.html")
        let cssText = read("app.css")
        let marked = read("marked.min.js")
        self.css = cssText
        if tpl.isEmpty {
            // 极简兜底（理论上不会走到）
            self.htmlShell = """
            <!DOCTYPE html><html><head><meta charset="utf-8"><style>body{font-family:-apple-system,"PingFang SC",sans-serif;line-height:1.8;max-width:860px;margin:0 auto;padding:48px 44px;}pre{background:#f5f5f7;padding:16px;border-radius:8px;overflow-x:auto}code{font-family:Menlo,monospace}</style></head>
            <body><article id="content"></article><script>\(marked)</script><script>
            window.__renderMD=function(b64,base){var bin=atob(b64),by=new Uint8Array(bin.length);for(var i=0;i<bin.length;i++)by[i]=bin.charCodeAt(i);var md=new TextDecoder("utf-8").decode(by);document.getElementById("content").innerHTML=marked.parse(md);window.scrollTo(0,0);return 0;};
            window.__setTheme=function(){};window.__setFontSize=function(px){document.body.style.fontSize=px+"px";};
            window.__contentHeight=function(){return document.body.scrollHeight;};window.__contentHTML=function(){return document.getElementById("content").innerHTML;};window.__ready=true;
            </script></body></html>
            """
        } else {
            self.htmlShell = tpl
                .replacingOccurrences(of: "/*__QUICKMD_CSS__*/", with: cssText)
                .replacingOccurrences(of: "/*__QUICKMD_MARKED__*/", with: marked)
        }
    }
}

// MARK: - 用户偏好
enum Prefs {
    static var fontSize: Int {
        get { UserDefaults.standard.object(forKey: "fontSize") as? Int ?? 16 }
        set { UserDefaults.standard.set(newValue, forKey: "fontSize") }
    }
    static var theme: String {
        get { UserDefaults.standard.string(forKey: "theme") ?? "auto" }
        set { UserDefaults.standard.set(newValue, forKey: "theme") }
    }
}

// MARK: - 文件读取（多编码兜底）
func readTextFile(_ path: String) -> (String, Int)? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
    if let s = String(data: data, encoding: .utf8) { return (s, data.count) }
    // GB18030（中文 Windows 记事本常见）
    let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(0x0632))
    if let s = String(data: data, encoding: gb) { return (s, data.count) }
    if let s = String(data: data, encoding: .windowsCP1252) { return (s, data.count) }
    if let s = String(data: data, encoding: .isoLatin1) { return (s, data.count) }
    return nil
}

func formatBytes(_ n: Int) -> String {
    if n < 1024 { return "\(n) B" }
    if n < 1024 * 1024 { return String(format: "%.1f KB", Double(n) / 1024) }
    return String(format: "%.2f MB", Double(n) / 1024 / 1024)
}

func countWords(_ s: String) -> Int {
    var c = 0
    var inWord = false
    for ch in s {
        if ch.isWhitespace || ch.isNewline { inWord = false }
        else if ch.isASCII { if !inWord { c += 1 }; inWord = true }
        else { c += 1; inWord = false } // 中文逐字计
    }
    return c
}

// MARK: - 可拖放容器
final class DropView: NSView {
    var onDropFiles: (([String]) -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { super.init(coder: coder); registerForDraggedTypes([.fileURL]) }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { return .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else { return false }
        let paths = urls.map { $0.path }.filter { isMarkdown($0) }
        if !paths.isEmpty { onDropFiles?(paths); return true }
        return false
    }
}

func isMarkdown(_ path: String) -> Bool {
    let ext = (path as NSString).pathExtension.lowercased()
    return ["md", "markdown", "mdown", "mkd", "mkdn", "mdtext", "rmd", "txt", "text"].contains(ext)
}

// MARK: - 主窗口
final class MDWindowController: NSWindowController, NSToolbarDelegate, WKNavigationDelegate, NSWindowDelegate {
    var webView: WKWebView!
    var statusLabel: NSTextField!
    var emptyView: NSView!
    var filePath: String?
    var webReady = false
    var pendingMD: (b64: String, base: String, path: String, bytes: Int, text: String)?
    var watchSource: DispatchSourceFileSystemObject?
    var watchFD: Int32 = -1
    var lastRenderMS: Double = 0
    let bootTime = Date()

    init() {
        let win = NSWindow(contentRect: NSMakeRect(0, 0, 1020, 760),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.center()
        win.title = "QuickMD"
        win.subtitle = "秒开 Markdown"
        win.setFrameAutosaveName("QuickMDMain")
        win.isReleasedWhenClosed = false
        super.init(window: win)
        win.delegate = self
        setupToolbar(win)
        setupViews(win)
        applyPrefsToWeb()
    }
    required init?(coder: NSCoder) { fatalError() }

    // ---- 工具栏 ----
    func setupToolbar(_ win: NSWindow) {
        let tb = NSToolbar(identifier: "QuickMDToolbar")
        tb.delegate = self
        tb.displayMode = .iconOnly
        tb.allowsUserCustomization = false
        win.toolbar = tb
        win.toolbarStyle = .unified
    }
    func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.open, .reload, .flexibleSpace, .expPDF, .expPNG, .expHTML, .flexibleSpace, .fontMinus, .fontPlus, .theme]
    }
    func toolbarDefaultItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.open, .reload, .flexibleSpace, .expPDF, .expPNG, .expHTML, .flexibleSpace, .fontMinus, .fontPlus, .theme]
    }
    func toolbar(_ t: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar f: Bool) -> NSToolbarItem? {
        func item(_ ident: NSToolbarItem.Identifier, _ symbol: String, _ label: String, _ tip: String, _ act: Selector) -> NSToolbarItem {
            let it = NSToolbarItem(itemIdentifier: ident)
            it.label = label
            it.toolTip = tip
            it.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            it.action = act
            it.target = self
            return it
        }
        switch id {
        case .open: return item(id, "folder", "打开", "打开 Markdown 文件 (⌘O)", #selector(openDocument(_:)))
        case .reload: return item(id, "arrow.clockwise", "重载", "重新载入 (⌘R)", #selector(reloadFile(_:)))
        case .expPDF: return item(id, "doc.richtext", "PDF", "导出 PDF (⌘E)", #selector(exportPDF(_:)))
        case .expPNG: return item(id, "photo", "长图", "导出超长图 PNG (⇧⌘E)", #selector(exportPNG(_:)))
        case .expHTML: return item(id, "globe", "HTML", "导出 HTML (⌘H)", #selector(exportHTML(_:)))
        case .fontMinus: return item(id, "textformat.size.smaller", "缩小", "缩小字号 (⌘-)", #selector(fontSmaller(_:)))
        case .fontPlus: return item(id, "textformat.size.larger", "放大", "放大字号 (⌘+)", #selector(fontBigger(_:)))
        case .theme: return item(id, "circle.lefthalf.filled", "主题", "切换主题：跟随/浅色/深色 (⌘T)", #selector(toggleTheme(_:)))
        default: return nil
        }
    }

    // ---- 视图 ----
    func setupViews(_ win: NSWindow) {
        let container = DropView(frame: win.contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        container.onDropFiles = { [weak self] paths in
            guard let self = self else { return }
            if self.filePath == nil { self.openFile(paths[0]) }
            else { (NSApp.delegate as? AppDelegate)?.openFiles(paths) }
        }
        win.contentView = container

        // WebView（预热：立即加载空模板）
        let cfg = WKWebViewConfiguration()
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)

        // 状态条
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.wantsLayer = true
        container.addSubview(bar)
        statusLabel = NSTextField(labelWithString: "就绪 — 把 .md 文件拖进来，或 ⌘O 打开")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bar.topAnchor),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 26),
            statusLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            statusLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -12),
        ])
        // 分隔线
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(line)
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: bar.topAnchor),
            line.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])

        // 空态
        emptyView = makeEmptyView()
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(emptyView)
        NSLayoutConstraint.activate([
            emptyView.topAnchor.constraint(equalTo: container.topAnchor),
            emptyView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            emptyView.bottomAnchor.constraint(equalTo: bar.topAnchor),
        ])

        // 立即加载模板（预热 Web 进程，后续渲染只是 JS 调用）
        webView.loadHTMLString(TemplateStore.shared.htmlShell, baseURL: Bundle.main.resourceURL)
    }

    func makeEmptyView() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        let t1 = NSTextField(labelWithString: "QuickMD 秒开预览")
        t1.font = .systemFont(ofSize: 22, weight: .semibold)
        t1.alignment = .center
        let t2 = NSTextField(labelWithString: "把 Markdown 文件拖到这里，或点击下方按钮打开\n支持 .md / .markdown / .mdown / .mkd / .txt")
        t2.font = .systemFont(ofSize: 13)
        t2.textColor = .secondaryLabelColor
        t2.alignment = .center
        let btn = NSButton(title: "打开文件…", target: self, action: #selector(openDocument(_:)))
        btn.bezelStyle = .rounded
        btn.font = .systemFont(ofSize: 14)
        let stack = NSStackView(views: [icon, t1, t2, btn])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56),
            stack.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }

    // ---- WK 代理：外链用浏览器打开 ----
    func webView(_ w: WKWebView, decidePolicyFor nav: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if nav.navigationType == .linkActivated, let url = nav.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
    func webView(_ w: WKWebView, didFinish nav: WKNavigation!) {
        webReady = true
        applyPrefsToWeb()
        if let p = pendingMD {
            pendingMD = nil
            renderPending(p)
        }
    }
    func webView(_ w: WKWebView, createWebViewWith cfg: WKWebViewConfiguration, for nav: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = nav.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    func applyPrefsToWeb() {
        guard webReady else { return }
        webView.evaluateJavaScript("window.__setTheme && __setTheme('\(Prefs.theme)')", completionHandler: nil)
        webView.evaluateJavaScript("window.__setFontSize && __setFontSize(\(Prefs.fontSize))", completionHandler: nil)
    }

    // MARK: - 打开 / 渲染
    func openFile(_ path: String) {
        let t0 = Date()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let (text, bytes) = readTextFile(path) else {
                DispatchQueue.main.async { self.toast("无法读取文件：\(path)") }
                return
            }
            let b64 = Data(text.utf8).base64EncodedString()
            let base = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent).absoluteString
            let words = countWords(text)
            let readMS = Date().timeIntervalSince(t0) * 1000
            DispatchQueue.main.async {
                self.filePath = path
                self.emptyView.isHidden = true
                self.window?.title = (path as NSString).lastPathComponent
                self.window?.subtitle = (path as NSString).deletingLastPathComponent
                NSDocumentController.shared.noteNewRecentDocumentURL(URL(fileURLWithPath: path))
                self.startWatching(path)
                let payload = (b64: b64, base: base, path: path, bytes: bytes, text: text)
                if self.webReady { self.renderPending(payload, readMS: readMS, words: words) }
                else { self.pendingMD = payload; self.pendingMeta = (readMS, words) }
            }
        }
    }
    var pendingMeta: (Double, Int)?

    func renderPending(_ p: (b64: String, base: String, path: String, bytes: Int, text: String), readMS: Double? = nil, words: Int? = nil) {
        let t0 = Date()
        // base64 只含 [A-Za-z0-9+/=]，可安全拼入 JS 单引号
        let js = "window.__renderMD('\(p.b64)','\(p.base)')"
        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            let jsMS = (result as? Double) ?? -1
            let totalMS = Date().timeIntervalSince(t0) * 1000 + (readMS ?? 0)
            self.lastRenderMS = jsMS
            let w = words ?? countWords(p.text)
            let info = "\(formatBytes(p.bytes)) · \(w) 字 · 渲染 \(String(format: "%.0f", jsMS >= 0 ? jsMS : totalMS)) ms"
            self.statusLabel.stringValue = info
        }
    }

    func startWatching(_ path: String) {
        stopWatching()
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchFD = fd
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        var last = Date.distantPast
        src.setEventHandler { [weak self] in
            guard let self = self else { return }
            let now = Date()
            if now.timeIntervalSince(last) < 0.4 { return }
            last = now
            // 文件被替换（rename）后重新打开
            if FileManager.default.fileExists(atPath: path) { self.openFile(path) }
        }
        src.setCancelHandler { Darwin.close(fd) }
        src.resume()
        watchSource = src
    }
    func stopWatching() {
        watchSource?.cancel(); watchSource = nil; watchFD = -1
    }

    func toast(_ msg: String) {
        statusLabel.stringValue = msg
        let alert = NSAlert()
        alert.messageText = msg
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - 菜单/工具栏动作
    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["md", "markdown", "mdown", "mkd", "mkdn", "mdtext", "rmd", "txt", "text"]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            let paths = panel.urls.map { $0.path }
            if filePath == nil, let first = paths.first {
                openFile(first)
                let rest = Array(paths.dropFirst())
                if !rest.isEmpty { (NSApp.delegate as? AppDelegate)?.openFiles(rest) }
            } else {
                (NSApp.delegate as? AppDelegate)?.openFiles(paths)
            }
        }
    }
    @objc func reloadFile(_ sender: Any?) {
        if let p = filePath { openFile(p) }
    }
    @objc func fontBigger(_ sender: Any?) { setFont(Prefs.fontSize + 1) }
    @objc func fontSmaller(_ sender: Any?) { setFont(Prefs.fontSize - 1) }
    @objc func fontReset(_ sender: Any?) { setFont(16) }
    func setFont(_ px: Int) {
        Prefs.fontSize = min(28, max(11, px))
        webView?.evaluateJavaScript("__setFontSize(\(Prefs.fontSize))", completionHandler: nil)
    }
    @objc func toggleTheme(_ sender: Any?) {
        let order = ["auto", "light", "dark"]
        let cur = order.firstIndex(of: Prefs.theme) ?? 0
        Prefs.theme = order[(cur + 1) % order.count]
        webView?.evaluateJavaScript("__setTheme('\(Prefs.theme)')", completionHandler: nil)
        statusLabel.stringValue = "主题：\(["跟随系统", "浅色", "深色"][(cur + 1) % 3])"
    }

    // MARK: - 导出
    func defaultExportName(_ ext: String) -> String {
        let base = ((filePath as NSString?)?.lastPathComponent as NSString?)?.deletingPathExtension ?? "QuickMD导出"
        return base + "." + ext
    }
    @objc func exportPDF(_ sender: Any?) {
        guard filePath != nil else { toast("先打开一个 Markdown 文件再导出"); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultExportName("pdf")
        panel.allowedFileTypes = ["pdf"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // A4 真分页：createPDF 只产单张长页，这里走打印管线存 PDF
        let pi = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        pi.paperSize = NSSize(width: 595.28, height: 841.89) // A4
        pi.orientation = .portrait
        pi.topMargin = 28.35; pi.bottomMargin = 28.35        // 窄边距 10mm
        pi.leftMargin = 28.35; pi.rightMargin = 28.35
        pi.horizontalPagination = .fit
        pi.verticalPagination = .automatic
        pi.jobDisposition = .save
        pi.dictionary().setObject(url as NSURL, forKey: "NSPrintJobSavingURL" as NSString)
        let op = webView.printOperation(with: pi)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        statusLabel.stringValue = "正在生成 PDF…"
        // run() 同步执行，放下一轮 runloop 先让状态条刷新
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if op.run(), let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int {
                self.statusLabel.stringValue = "已导出 PDF：\(url.lastPathComponent) (\(formatBytes(size)))"
            } else {
                self.statusLabel.stringValue = "PDF 生成失败或已取消"
            }
        }
    }
    @objc func exportHTML(_ sender: Any?) {
        guard filePath != nil else { toast("先打开一个 Markdown 文件再导出"); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultExportName("html")
        panel.allowedFileTypes = ["html"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        webView.evaluateJavaScript("window.__contentHTML()") { [weak self] result, _ in
            guard let self = self, let inner = result as? String else { return }
            let title = ((self.filePath as NSString?)?.lastPathComponent as NSString?)?.deletingPathExtension ?? "QuickMD"
            let doc = """
            <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>\(title)</title><style>\(TemplateStore.shared.css)</style></head><body><article id="content">\(inner)</article></body></html>
            """
            do { try doc.write(to: url, atomically: true, encoding: .utf8); self.statusLabel.stringValue = "已导出 HTML：\(url.lastPathComponent)" }
            catch { self.toast("HTML 写入失败：\(error.localizedDescription)") }
        }
    }
    @objc func exportPNG(_ sender: Any?) {
        guard filePath != nil else { toast("先打开一个 Markdown 文件再导出"); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultExportName("png")
        panel.allowedFileTypes = ["png"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        statusLabel.stringValue = "正在生成长图…"
        webView.evaluateJavaScript("window.__contentHeight()") { [weak self] result, _ in
            guard let self = self else { return }
            let h = max(200, min(Int((result as? Double) ?? 1200), 60000))
            self.snapshotFull(height: h) { image in
                guard let img = image, let tiff = img.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    self.toast("长图生成失败"); return
                }
                do { try png.write(to: url); self.statusLabel.stringValue = "已导出长图：\(url.lastPathComponent) (\(formatBytes(png.count)))" }
                catch { self.toast("长图写入失败：\(error.localizedDescription)") }
            }
        }
    }
    /// 全内容快照：临时拉高 WebView 后截图（分片拼接，支持超长）
    func snapshotFull(height: Int, completion: @escaping (NSImage?) -> Void) {
        let cfg = WKSnapshotConfiguration()
        let origFrame = webView.frame
        let width = Int(origFrame.width)
        let sliceH = 4000
        if height <= sliceH + 500 {
            // 单张搞定
            webView.frame = NSRect(x: origFrame.origin.x, y: origFrame.origin.y, width: CGFloat(width), height: CGFloat(height))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self = self else { return }
                self.webView.takeSnapshot(with: cfg) { img, _ in
                    self.webView.frame = origFrame
                    completion(img)
                }
            }
            return
        }
        // 超长：分片 + 拼接
        var slices: [NSImage] = []
        var y = 0
        // 先拉高到全高，保证布局完整
        webView.frame = NSRect(x: origFrame.origin.x, y: origFrame.origin.y, width: CGFloat(width), height: CGFloat(height))
        func next() {
            let remain = height - y
            if remain <= 0 {
                self.webView.frame = origFrame
                completion(stitch(slices, width: width, height: height))
                return
            }
            let h = min(sliceH, remain)
            let c = WKSnapshotConfiguration()
            c.rect = CGRect(x: 0, y: y, width: width, height: h)
            self.webView.takeSnapshot(with: c) { img, _ in
                if let im = img { slices.append(im) }
                y += h
                next()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { next() }
    }

    func windowWillClose(_ n: Notification) { stopWatching() }
}

/// 分片拼成长图
func stitch(_ slices: [NSImage], width: Int, height: Int) -> NSImage? {
    guard !slices.isEmpty else { return nil }
    if slices.count == 1 { return slices[0] }
    let scale: CGFloat = 2.0 // Retina
    guard let ctx = CGContext(data: nil, width: width * Int(scale), height: height * Int(scale),
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return slices[0] }
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width * Int(scale), height: height * Int(scale)))
    var y: CGFloat = 0
    for s in slices {
        guard let cg = s.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
        // 按宽度缩放绘制
        let srcW = CGFloat(cg.width), srcH = CGFloat(cg.height)
        let drawW = CGFloat(width) * scale
        let drawH = drawW * srcH / srcW
        // CG 坐标原点在左下，需要倒置
        let flipY = CGFloat(height) * scale - y - drawH
        ctx.draw(cg, in: CGRect(x: 0, y: flipY, width: drawW, height: drawH))
        y += drawH
    }
    guard let out = ctx.makeImage() else { return slices[0] }
    return NSImage(cgImage: out, size: NSSize(width: width, height: height))
}

extension NSToolbarItem.Identifier {
    static let open = NSToolbarItem.Identifier("open")
    static let reload = NSToolbarItem.Identifier("reload")
    static let expPDF = NSToolbarItem.Identifier("expPDF")
    static let expPNG = NSToolbarItem.Identifier("expPNG")
    static let expHTML = NSToolbarItem.Identifier("expHTML")
    static let fontMinus = NSToolbarItem.Identifier("fontMinus")
    static let fontPlus = NSToolbarItem.Identifier("fontPlus")
    static let theme = NSToolbarItem.Identifier("theme")
}

// MARK: - AppDelegate
final class AppDelegate: NSObject, NSApplicationDelegate {
    func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. App 菜单
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(withTitle: "关于 QuickMD", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())

        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "服务")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "隐藏 QuickMD", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 QuickMD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // 2. 文件菜单
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "文件")
        fileMenuItem.submenu = fileMenu

        fileMenu.addItem(withTitle: "新建窗口", action: #selector(menuNewWindow(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "打开…", action: #selector(menuOpenDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "重新载入", action: #selector(menuReloadFile(_:)), keyEquivalent: "r")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "导出 PDF…", action: #selector(menuExportPDF(_:)), keyEquivalent: "e")
        let expPngItem = NSMenuItem(title: "导出长图 PNG…", action: #selector(menuExportPNG(_:)), keyEquivalent: "E")
        expPngItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(expPngItem)
        fileMenu.addItem(withTitle: "导出 HTML…", action: #selector(menuExportHTML(_:)), keyEquivalent: "")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        // 3. 编辑菜单（支持 ⌘C / ⌘V / ⌘A 等标准文本操作）
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: Selector(("selectAll:")), keyEquivalent: "a")

        // 4. 显示菜单
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "显示")
        viewMenuItem.submenu = viewMenu
        let bigger = NSMenuItem(title: "放大字号", action: #selector(menuFontBigger(_:)), keyEquivalent: "=")
        bigger.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(bigger)
        viewMenu.addItem(withTitle: "缩小字号", action: #selector(menuFontSmaller(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "默认字号", action: #selector(menuFontReset(_:)), keyEquivalent: "0")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "切换主题", action: #selector(menuToggleTheme(_:)), keyEquivalent: "t")

        // 5. 窗口菜单
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    var keyWindowController: MDWindowController? {
        if let keyWin = NSApp.keyWindow, let c = keyWin.windowController as? MDWindowController {
            return c
        }
        for c in controllers {
            if c.window?.isKeyWindow ?? false { return c }
        }
        return controllers.last
    }

    @objc func menuNewWindow(_ sender: Any?) {
        newWindow().showWindow(nil)
    }

    @objc func menuOpenDocument(_ sender: Any?) {
        if let c = keyWindowController {
            c.openDocument(sender)
        } else {
            let c = newWindow()
            c.showWindow(nil)
            c.openDocument(sender)
        }
    }

    @objc func menuReloadFile(_ sender: Any?) {
        keyWindowController?.reloadFile(sender)
    }

    @objc func menuExportPDF(_ sender: Any?) {
        keyWindowController?.exportPDF(sender)
    }

    @objc func menuExportPNG(_ sender: Any?) {
        keyWindowController?.exportPNG(sender)
    }

    @objc func menuExportHTML(_ sender: Any?) {
        keyWindowController?.exportHTML(sender)
    }

    @objc func menuFontBigger(_ sender: Any?) {
        keyWindowController?.fontBigger(sender)
    }

    @objc func menuFontSmaller(_ sender: Any?) {
        keyWindowController?.fontSmaller(sender)
    }

    @objc func menuFontReset(_ sender: Any?) {
        keyWindowController?.fontReset(sender)
    }

    @objc func menuToggleTheme(_ sender: Any?) {
        keyWindowController?.toggleTheme(sender)
    }

    var controllers: [MDWindowController] = []
    var pendingPaths: [String] = []
    var didLaunch = false

    func applicationDidFinishLaunching(_ n: Notification) {
        setupMainMenu()
        didLaunch = true
        // 命令行参数（open xxx.md / 拖到 Dock 图标）
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0) }
        if !args.isEmpty { openFiles(Array(args)) }
        else if !pendingPaths.isEmpty { openFiles(pendingPaths); pendingPaths = [] }
        else { newWindow().showWindow(nil) } // 空态
        NSApp.activate(ignoringOtherApps: true)
    }
    func application(_ app: NSApplication, openFile filename: String) -> Bool {
        if !didLaunch { pendingPaths.append(filename); return true }
        openFiles([filename]); return true
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if !didLaunch { pendingPaths.append(contentsOf: filenames); return }
        openFiles(filenames)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newWindow().showWindow(nil) }
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { return false }

    @discardableResult
    func newWindow() -> MDWindowController {
        let c = MDWindowController()
        controllers.append(c)
        // 清理已关闭的
        controllers = controllers.filter { $0.window?.isVisible ?? false || $0.filePath == nil }
        return c
    }
    func openFiles(_ paths: [String]) {
        let mds = paths.filter { isMarkdown($0) || FileManager.default.fileExists(atPath: $0) }
        guard !mds.isEmpty else { return }
        // 复用空窗口
        if let empty = controllers.first(where: { $0.filePath == nil && ($0.window?.isVisible ?? false) }) {
            empty.showWindow(nil)
            empty.openFile(mds[0])
            for p in mds.dropFirst() { let c = newWindow(); c.showWindow(nil); c.openFile(p) }
        } else {
            for p in mds { let c = newWindow(); c.showWindow(nil); c.openFile(p) }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - main
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
