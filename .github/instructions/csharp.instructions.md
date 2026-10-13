---
applyTo: "**/*.cs"
---

# C# conventions

- Target .NET 9 with nullable reference types enabled and warnings treated as errors. Fix warnings; do not suppress them without a justification comment.
- Use the minimal API style:
  - Group endpoints with `MapGroup` or extension methods.
  - Return `TypedResults` so OpenAPI metadata is inferred.
- Use file-scoped namespaces, `sealed` classes by default, and records for DTOs.
- Use structured logging with message templates, for example `logger.LogInformation("Served {Count} items", count)`. Never use string interpolation in log calls.
- Configuration comes from environment variables or `appsettings*.json`. Never hard-code secrets.
- **Tests:**
  - Use xUnit with `WebApplicationFactory<Program>` for endpoint behaviour.
  - Name tests `Method_Scenario_Expectation`.
  - Every new endpoint needs at least one integration test.
- Add package versions to `Directory.Packages.props` (central package management), not to `.csproj` files.
