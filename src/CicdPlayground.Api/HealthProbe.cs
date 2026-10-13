namespace CicdPlayground.Api;

/// <summary>
/// Minimal out-of-process health probe used by container health checks in
/// images that have no shell or curl (for example chiseled .NET images).
/// </summary>
internal static class HealthProbe
{
    public const string Argument = "--health-probe";

    public static async Task<int> RunAsync()
    {
        // HEALTH_PROBE_URL lets you override the target; the default matches the
        // port configured by ASPNETCORE_HTTP_PORTS=8080 in the Dockerfile.
        var url = Environment.GetEnvironmentVariable("HEALTH_PROBE_URL") ?? "http://localhost:8080/health";

        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };
        try
        {
            using var response = await client.GetAsync(new Uri(url)).ConfigureAwait(false);
            return response.IsSuccessStatusCode ? 0 : 1;
        }
        catch (HttpRequestException)
        {
            return 1;
        }
        catch (TaskCanceledException)
        {
            return 1;
        }
    }
}
