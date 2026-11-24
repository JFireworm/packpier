using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace Packpier.Windows;

internal sealed record CatalogEntry(string Id, string App, string Version,
    Dictionary<string, string> Name, Dictionary<string, string> Summary);

internal sealed record Plugin(string Id, string Name, string Version, string Summary);

internal static class Marketplace
{
    internal static Plugin[] Read(Stream catalog, CultureInfo language)
    {
        string Localize(Dictionary<string, string> values)
        {
            for (var culture = language; culture != CultureInfo.InvariantCulture; culture = culture.Parent)
                if (values.TryGetValue(culture.Name, out var translation)) return translation;
            return values["en"];
        }

        var entries = JsonSerializer.Deserialize<CatalogEntry[]>(catalog, JsonSerializerOptions.Web)
            ?? throw new InvalidDataException("Empty plugin catalog");
        return entries.Where(entry => entry.App == "codex")
            .Select(entry => new Plugin(entry.Id, Localize(entry.Name), entry.Version, Localize(entry.Summary)))
            .ToArray();
    }
}
