using System.Text.Json.Serialization;

namespace CicdPlayground.Api;

/// <summary>Build metadata, populated from environment variables at startup.</summary>
internal sealed class BuildInfo
{
    public string Version { get; set; } = "local";
    public string CommitSha { get; set; } = "unknown";
    public string Environment { get; set; } = "Production";
}

internal sealed record ServiceInfo(
    string Name,
    string Version,
    string CommitSha,
    string Environment,
    DateTimeOffset ServerTimeUtc);

internal sealed record WeatherForecast(DateOnly Date, int TemperatureC, string Summary)
{
    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
}

/// <summary>
/// Compile-time JSON serialization metadata. The source generator writes the
/// serialization code during build, so no reflection is needed at runtime.
/// </summary>
[JsonSerializable(typeof(ServiceInfo))]
[JsonSerializable(typeof(WeatherForecast[]))]
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class AppJsonSerializerContext : JsonSerializerContext;
