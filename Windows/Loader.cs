namespace Packpier.Windows;

internal enum LoaderStatus { Unavailable }

internal interface ILoader
{
    LoaderStatus Status { get; }
}

internal sealed class PreviewLoader : ILoader
{
    public LoaderStatus Status => LoaderStatus.Unavailable;
}
