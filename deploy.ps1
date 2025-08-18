#!/usr/bin/env pwsh
param()

$files = @('compose.download.yml', 'compose.worker.yml')
foreach ($file in $files) {
  if (Test-Path $file) {
    docker compose -f $file up -d
  } else {
    Write-Host "Missing $file; skipping."
  }
}
