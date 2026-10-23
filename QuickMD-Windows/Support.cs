// QuickMD for Windows — 模板缓存、偏好设置、工具函数、默认打开注册
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using Microsoft.Win32;

namespace QuickMD;

// 与 mac 版 TemplateStore 同思路：模板只读一次，后续渲染只是 JS 调用
sealed class TemplateStore
{
    public static TemplateStore Shared { get; } = new();
    public string HtmlShell { get; }
    public string Css { get; }

    private TemplateStore()
    {
        string tpl = Read("template.html");
        string css = Read("app.css");
        string marked = Read("marked.min.js");
        Css = css;
        if (string.IsNullOrEmpty(tpl))
        {
            // 极简兜底（理论上不会走到）
            HtmlShell = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><style>body{font-family:\"Microsoft YaHei\",sans-serif;line-height:1.8;max-width:860px;margin:0 auto;padding:48px 44px;}pre{background:#f5f5f7;padding:16px;border-radius:8px;overflow-x:auto}code{font-family:Consolas,monospace}</style></head>"
                + "<body><article id=\"content\"></article><script>" + marked + "</script><script>"
                + "window.__renderMD=function(b64,base){var bin=atob(b64),by=new Uint8Array(bin.length);for(var i=0;i<bin.length;i++)by[i]=bin.charCodeAt(i);var md=new TextDecoder(\"utf-8\").decode(by);document.getElementById(\"content\").innerHTML=marked.parse(md);window.scrollTo(0,0);return 0;};"
                + "window.__setTheme=function(){};window.__setFontSize=function(px){document.body.style.fontSize=px+\"px\";};"
                + "window.__contentHeight=function(){return document.body.scrollHeight;};window.__contentHTML=function(){return document.getElementById(\"content\").innerHTML;};window.__ready=true;"
                + "</script></body></html>";
        }
        else
        {
            HtmlShell = tpl.Replace("/*__QUICKMD_CSS__*/", css).Replace("/*__QUICKMD_MARKED__*/", marked);
        }
    }

    static string Read(string name)
    {
        try
        {
            // 1) exe 旁的 Resources/ 优先（方便调试/自定义样式）
            string exeDir = AppContext.BaseDirectory;
            string p1 = Path.Combine(exeDir, "Resources", name);
            if (File.Exists(p1)) return File.ReadAllText(p1, Encoding.UTF8);
            string p2 = Path.Combine(exeDir, name);
            if (File.Exists(p2)) return File.ReadAllText(p2, Encoding.UTF8);
            // 2) 内嵌资源（单文件 exe 的正常路径）
            var asm = Assembly.GetExecutingAssembly();
            using Stream? s = asm.GetManifestResourceStream("QuickMD.Resources." + name);
            if (s != null)
            {
                using var r = new StreamReader(s, Encoding.UTF8);
                return r.ReadToEnd();
            }
        }
        catch { }
        return "";
    }
}

sealed class PrefsData
{
    public int FontSize { get; set; } = 16;
    public string Theme { get; set; } = "auto";
}

// 偏好：%AppData%/QuickMD/settings.json（对标 mac 版 UserDefaults）
static class Prefs
{
    static readonly string FilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "QuickMD", "settings.json");
    static PrefsData _d = Load();

    static PrefsData Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<PrefsData>(File.ReadAllText(FilePath)) ?? new PrefsData();
        }
        catch { }
        return new PrefsData();
    }

    public static int FontSize
    {
        get => _d.FontSize is >= 11 and <= 28 ? _d.FontSize : 16;
        set { _d.FontSize = Math.Clamp(value, 11, 28); Save(); }
    }

    public static string Theme
    {
        get => _d.Theme is "light" or "dark" ? _d.Theme : "auto";
        set { _d.Theme = value; Save(); }
    }

    static void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(_d));
        }
        catch { }
    }
}

static class Utils
{
    // 多编码兜底：UTF-8 → GB18030 → Win1252 → Latin1（对标 mac 版）
    public static (string Text, int Bytes)? ReadTextFile(string path)
    {
        byte[] data;
        try { data = File.ReadAllBytes(path); }
        catch { return null; }
        try
        {
            string s = new UTF8Encoding(false, true).GetString(data);
            return (s.TrimStart('\uFEFF'), data.Length);
        }
        catch { }
        try { return (Encoding.GetEncoding("GB18030").GetString(data), data.Length); }
        catch { }
        try { return (Encoding.GetEncoding(1252).GetString(data), data.Length); }
        catch { }
        return (Encoding.Latin1.GetString(data), data.Length);
    }

    public static string FormatBytes(int n)
    {
        if (n < 1024) return n + " B";
        if (n < 1024 * 1024) return (n / 1024.0).ToString("0.0") + " KB";
        return (n / 1024.0 / 1024.0).ToString("0.00") + " MB";
    }

    public static int CountWords(string s)
    {
        int c = 0;
        bool inWord = false;
        foreach (char ch in s)
        {
            if (char.IsWhiteSpace(ch)) inWord = false;
            else if (ch < 128) { if (!inWord) c++; inWord = true; }
            else { c++; inWord = false; } // 中文逐字计
        }
        return c;
    }

    public static bool IsMarkdown(string path)
    {
        string ext = Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
        return ext is "md" or "markdown" or "mdown" or "mkd" or "mkdn" or "mdtext" or "rmd" or "txt" or "text";
    }
}

// 注册 .md 默认打开（HKCU，无需管理员权限）
static class DefaultApp
{
    public static string TryRegister()
    {
        try
        {
            string exe = Environment.ProcessPath ?? Application.ExecutablePath;
            string[] exts = new[] { ".md", ".markdown", ".mdown", ".mkd", ".mkdn", ".mdtext", ".rmd" };
            foreach (string ext in exts)
            {
                using var k = Registry.CurrentUser.CreateSubKey(@"Software\Classes\" + ext);
                k?.SetValue("", "QuickMD.Document");
            }
            using (var prog = Registry.CurrentUser.CreateSubKey(@"Software\Classes\QuickMD.Document"))
                prog?.SetValue("", "Markdown 文档 (QuickMD)");
            using (var cmd = Registry.CurrentUser.CreateSubKey(@"Software\Classes\QuickMD.Document\shell\open\command"))
                cmd?.SetValue("", "\"" + exe + "\" \"%1\"");
            using (var icon = Registry.CurrentUser.CreateSubKey(@"Software\Classes\QuickMD.Document\DefaultIcon"))
                icon?.SetValue("", "\"" + exe + "\",0");
            SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero); // SHCNE_ASSOCCHANGED
            return "ok";
        }
        catch (Exception ex) { return ex.Message; }
    }

    [DllImport("shell32.dll")]
    static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);
}
