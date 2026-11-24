using System;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Automation;

namespace Packpier.Windows;

public partial class MainWindow : Window
{
    public MainWindow() : this(new PreviewLoader()) { }

    internal MainWindow(ILoader loader)
    {
        InitializeComponent();
        var language = CultureInfo.CurrentUICulture;
        var chinese = language.TwoLetterISOLanguageName == "zh";
        Heading.Text = chinese ? "插件市场" : "Plugin marketplace";
        AutomationProperties.SetName(Plugins, Heading.Text);
        Status.Text = loader.Status switch
        {
            LoaderStatus.Unavailable => chinese ? "只读预览 · Windows 加载器尚未接入" :
                "Read-only preview · Windows loader unavailable",
            _ => throw new ArgumentOutOfRangeException(nameof(loader))
        };
        using var catalog = typeof(MainWindow).Assembly.GetManifestResourceStream("Packpier.Marketplace.json")
            ?? throw new FileNotFoundException("The built-in marketplace catalog is missing.");
        Plugins.ItemsSource = Marketplace.Read(catalog, language);
        if (Plugins.Items.Count > 0) Plugins.SelectedIndex = 0;
    }
}
