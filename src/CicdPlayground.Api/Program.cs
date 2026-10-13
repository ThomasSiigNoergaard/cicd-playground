using CicdPlayground.Api;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.Options;

// Chiseled (distroless style) images contain no shell, curl or wget, so a classic
// "HEALTHCHECK CMD curl ..." is impossible. Instead the app binary doubles as its
// own probe: "dotnet CicdPlayground.Api.dll --health-probe" calls /health on
// localhost and exits 0 (healthy) or 1 (unhealthy). See Dockerfile and the ECS
// task definition healthCheck.
if (args.Contains(HealthProbe.Argument, StringComparer.Ordinal))
{
    return await HealthProbe.RunAsync();
}

var builder = WebApplication.CreateSlimBuilder(args);

// Structured JSON logging: one JSON object per log line on stdout. Log shippers
// such as CloudWatch Logs Insights can then query fields instead of parsing text.
builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole(options =>
{
    options.IncludeScopes = true;
    options.UseUtcTimestamp = true;
    options.TimestampFormat = "yyyy-MM-ddTHH:mm:ss.fffZ";
});

// Build metadata is injected by the container image and the ECS task definition
// as environment variables, so the running app can tell you exactly what it is.
builder.Services.AddOptions<BuildInfo>()
    .Configure(info =>
    {
        info.Version = Environment.GetEnvironmentVariable("APP_VERSION") ?? "local";
        info.CommitSha = Environment.GetEnvironmentVariable("GIT_COMMIT_SHA") ?? "unknown";
        info.Environment = builder.Environment.EnvironmentName;
    });

// Source-generated JSON serialization: faster, trimming friendly, and no reflection.
builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonSerializerContext.Default));

// Injecting TimeProvider instead of calling DateTime.UtcNow makes time testable
// (tests can swap in a FakeTimeProvider).
builder.Services.AddSingleton(TimeProvider.System);

// ASP.NET Core health checks. The ALB target group and the container HEALTHCHECK
// both call /health. Add real dependency checks (database, queues) here later.
builder.Services.AddHealthChecks();

// Built-in OpenAPI document generation (Microsoft.AspNetCore.OpenApi, .NET 9+).
builder.Services.AddOpenApi();

var app = builder.Build();

// The OpenAPI document is served at /openapi/v1.json. It is harmless metadata
// for this demo, so it is exposed in every environment.
app.MapOpenApi();

app.MapGet("/", (IOptions<BuildInfo> info, TimeProvider clock) => TypedResults.Ok(new ServiceInfo(
        Name: "CicdPlayground.Api",
        Version: info.Value.Version,
        CommitSha: info.Value.CommitSha,
        Environment: info.Value.Environment,
        ServerTimeUtc: clock.GetUtcNow())))
    .WithName("GetServiceInfo")
    .WithSummary("Returns service name, version and the git commit it was built from.");

app.MapHealthChecks("/health", new HealthCheckOptions
{
    // Keep the default plain text "Healthy"/"Unhealthy" response; load balancers only need the status code.
    AllowCachingResponses = false,
}).WithName("Health");

string[] summaries = ["Freezing", "Bracing", "Chilly", "Cool", "Mild", "Warm", "Balmy", "Hot", "Sweltering", "Scorching"];

app.MapGet("/weatherforecast", (TimeProvider clock) =>
    {
        var today = DateOnly.FromDateTime(clock.GetUtcNow().UtcDateTime);
        var forecast = Enumerable.Range(1, 5)
            .Select(index => new WeatherForecast(
                today.AddDays(index),
                Random.Shared.Next(-20, 55),
                summaries[Random.Shared.Next(summaries.Length)]))
            .ToArray();
        return TypedResults.Ok(forecast);
    })
    .WithName("GetWeatherForecast")
    .WithSummary("Returns a random five day weather forecast (demo data).");

await app.RunAsync();
return 0;

/// <summary>Exposes the compiler generated Program class to the integration tests.</summary>
public partial class Program;
