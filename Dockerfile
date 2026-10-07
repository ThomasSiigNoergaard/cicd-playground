# syntax=docker/dockerfile:1
#
# Multi-stage build:
#   1. "build" uses the full .NET SDK image to restore, compile and publish.
#   2. "final" uses the chiseled ASP.NET runtime image: Ubuntu based, but with no
#      shell, no package manager and a non-root user by default. That removes most
#      of the attack surface (and most CVEs that scanners like Trivy would report).
#
# Base images are pinned by tag AND digest. The tag documents intent, the digest
# makes the build reproducible. Dependabot (docker ecosystem) bumps both. The
# references are written directly in the FROM lines (not via ARG) because
# Dependabot only parses literal FROM images.


# ---------------------------------------------------------------------------
# Stage 1: build
# ---------------------------------------------------------------------------
# --platform=$BUILDPLATFORM runs the SDK natively on the build machine even when
# cross-building for another architecture, which is much faster than emulation.
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:9.0-noble@sha256:64c94a5a8fac55f965e0fb74b0e6a46b73b7323257c492170befbe5537dfafef AS build
ARG TARGETARCH
WORKDIR /source

# Copy only the files that affect restore first. Docker caches this layer, so
# "dotnet restore" is skipped on rebuilds unless dependencies changed.
COPY global.json Directory.Build.props Directory.Packages.props ./
COPY src/CicdPlayground.Api/CicdPlayground.Api.csproj src/CicdPlayground.Api/packages.lock.json src/CicdPlayground.Api/
# The BuildKit cache mount keeps the NuGet package folder between builds without
# baking it into an image layer.
RUN --mount=type=cache,id=nuget,target=/root/.nuget/packages \
    dotnet restore src/CicdPlayground.Api/CicdPlayground.Api.csproj --locked-mode

COPY src/ src/
RUN --mount=type=cache,id=nuget,target=/root/.nuget/packages \
    dotnet publish src/CicdPlayground.Api/CicdPlayground.Api.csproj \
      --no-restore -c Release -o /app \
      -p:UseAppHost=false

# ---------------------------------------------------------------------------
# Stage 2: runtime
# ---------------------------------------------------------------------------
FROM mcr.microsoft.com/dotnet/aspnet:9.0-noble-chiseled@sha256:d096bdef27132e73dd09176abf68fdcec2c9751c33b02c2b0493fc41c3ef87fc AS final

# Build metadata surfaced by GET /. CI passes these as --build-arg.
ARG APP_VERSION=local
ARG GIT_COMMIT_SHA=unknown

# OCI labels make the image self-describing (registries and scanners read them).
LABEL org.opencontainers.image.title="CicdPlayground.Api" \
      org.opencontainers.image.source="https://github.com/ThomasSiigNoergaard/cicd-playground" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT_SHA}"

ENV APP_VERSION=${APP_VERSION} \
    GIT_COMMIT_SHA=${GIT_COMMIT_SHA} \
    ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_gcServer=0

WORKDIR /app
COPY --from=build /app .

# Run as the unprivileged "app" user (UID 1654) that the .NET images define as
# $APP_UID. Using the numeric UID lets Kubernetes/ECS verify runAsNonRoot.
USER $APP_UID

# 8080 is unprivileged, so a non-root process can bind to it.
EXPOSE 8080

# No curl or shell in a chiseled image, so the app binary probes itself (see
# src/CicdPlayground.Api/HealthProbe.cs). Exec form avoids needing /bin/sh.
# Note: ECS ignores Docker HEALTHCHECK; the task definition declares its own
# healthCheck using the same command, and the ALB checks /health independently.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD ["dotnet", "CicdPlayground.Api.dll", "--health-probe"]

ENTRYPOINT ["dotnet", "CicdPlayground.Api.dll"]
