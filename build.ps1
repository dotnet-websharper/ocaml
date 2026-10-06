$ErrorActionPreference = "Stop"
Push-Location frontend
dune build
Pop-Location
Push-Location backend
dotnet build -c Release
Pop-Location
Write-Host "Build complete."
