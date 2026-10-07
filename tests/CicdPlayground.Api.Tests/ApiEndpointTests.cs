using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;

namespace CicdPlayground.Api.Tests;

/// <summary>
/// Integration tests: WebApplicationFactory boots the real app in memory (full
/// middleware pipeline, DI and routing) and gives us an HttpClient that talks to
/// it without opening a network port. Fast, and much closer to production than
/// unit tests of individual handlers.
/// </summary>
public sealed class ApiEndpointTests(WebApplicationFactory<Program> factory)
    : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client = factory.CreateClient();

    [Fact]
    public async Task Root_returns_service_info()
    {
        var response = await _client.GetAsync(new Uri("/", UriKind.Relative), TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));
        Assert.Equal("CicdPlayground.Api", json.RootElement.GetProperty("name").GetString());
        Assert.False(string.IsNullOrWhiteSpace(json.RootElement.GetProperty("version").GetString()));
        Assert.False(string.IsNullOrWhiteSpace(json.RootElement.GetProperty("commitSha").GetString()));
    }

    [Fact]
    public async Task Health_returns_healthy()
    {
        var response = await _client.GetAsync(new Uri("/health", UriKind.Relative), TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("Healthy", await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task WeatherForecast_returns_five_days()
    {
        var forecast = await _client.GetFromJsonAsync<JsonElement[]>(
            new Uri("/weatherforecast", UriKind.Relative), TestContext.Current.CancellationToken);

        Assert.NotNull(forecast);
        Assert.Equal(5, forecast.Length);
        Assert.All(forecast, day => Assert.True(day.TryGetProperty("temperatureC", out _)));
    }

    [Fact]
    public async Task OpenApi_document_is_served()
    {
        var response = await _client.GetAsync(new Uri("/openapi/v1.json", UriKind.Relative), TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("/weatherforecast", await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken), StringComparison.Ordinal);
    }

    [Fact]
    public async Task Unknown_route_returns_not_found()
    {
        var response = await _client.GetAsync(new Uri("/does-not-exist", UriKind.Relative), TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}
