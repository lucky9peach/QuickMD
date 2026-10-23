// QuickMD for Windows — 入口 + 多窗口管理（对标 mac 版 AppDelegate）
using System.Text;

namespace QuickMD;

static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance); // GB18030 / Win1252
        ApplicationConfiguration.Initialize();
        string[] files = args.Where(a => !a.StartsWith("-") && File.Exists(a)).ToArray();
        Application.Run(new MultiWindowContext(files));
    }

    public static void OpenFiles(IEnumerable<string> paths) => MultiWindowContext.Current?.OpenFiles(paths);
    public static void NewWindow() => MultiWindowContext.Current?.NewEmptyWindow();
}

sealed class MultiWindowContext : ApplicationContext
{
    public static MultiWindowContext? Current { get; private set; }
    readonly List<MainForm> _forms = new();

    public MultiWindowContext(string[] initial)
    {
        Current = this;
        if (initial.Length == 0) NewEmptyWindow();
        else OpenFiles(initial);
        if (_forms.Count == 0) NewEmptyWindow();
    }

    public void NewEmptyWindow()
    {
        var f = new MainForm();
        Track(f);
        f.Show();
    }

    public void OpenFiles(IEnumerable<string> paths)
    {
        List<string> list = paths.Where(File.Exists).ToList();
        if (list.Count == 0) return;
        // 复用空窗口
        MainForm? empty = _forms.FirstOrDefault(f => f.FilePath == null && f.Visible);
        bool first = true;
        foreach (string p in list)
        {
            if (first && empty != null) { empty.Activate(); empty.OpenFile(p); }
            else { var f = new MainForm(); Track(f); f.Show(); f.OpenFile(p); }
            first = false;
        }
    }

    void Track(MainForm f)
    {
        _forms.Add(f);
        f.FormClosed += (_, _) =>
        {
            _forms.Remove(f);
            if (_forms.Count == 0) ExitThread();
        };
    }
}
