FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

# Copy published / compiled binaries
COPY src/DukaLedger.Api/bin/Debug/net8.0/ ./

# Expose HTTP port
EXPOSE 5080
ENV ASPNETCORE_URLS=http://0.0.0.0:5080
ENV ASPNETCORE_ENVIRONMENT=Production

ENTRYPOINT ["dotnet", "DukaLedger.Api.dll", "--urls", "http://0.0.0.0:5080"]
