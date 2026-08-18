@echo off
title Addons-init - Bootstrap for Addons-Fetcher
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$env:INIT_SELF='%~f0'; $env:INIT_DIR='%~dp0'; $c=[IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8); $m=([char]10).ToString()+'#PS'+'START'; $i=$c.IndexOf($m); if($i -lt 0){ Write-Host 'Script marker not found.'; exit 1 }; Invoke-Expression ($c.Substring($i+$m.Length))"
exit /b %ERRORLEVEL%
#PSSTART
# ============================================================================
#  Addons-init
#  Bootstrap script: downloads the latest Addons-Fetcher.cmd from the
#  Addons-SoD/Addons-Fetcher repository into the current directory and
#  runs it. The fetcher then deploys all addons into this directory.
#  Download sources are tried in order: raw.githubusercontent.com,
#  github.com raw redirect, jsDelivr CDN.
# ============================================================================
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$ScriptDir   = ($env:INIT_DIR).TrimEnd('\')
$Owner       = 'Addons-SoD'
$Repo        = 'Addons-Fetcher'
$Branch      = 'main'
$FetcherName = 'Addons-Fetcher.cmd'

$urls = @(
  ('https://raw.githubusercontent.com/' + $Owner + '/' + $Repo + '/' + $Branch + '/' + $FetcherName),
  ('https://github.com/' + $Owner + '/' + $Repo + '/raw/' + $Branch + '/' + $FetcherName),
  ('https://cdn.jsdelivr.net/gh/' + $Owner + '/' + $Repo + '@' + $Branch + '/' + $FetcherName)
)

$target = Join-Path $ScriptDir $FetcherName
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host '  Addons-init: fetching Addons-Fetcher.cmd' -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan
$ok = $false
foreach ($u in $urls) {
  Write-Host ('Trying ' + $u + ' ...') -ForegroundColor Gray
  try {
    Invoke-WebRequest -Uri $u -OutFile $target -UseBasicParsing -TimeoutSec 120
    if ((Test-Path -LiteralPath $target) -and (Get-Item -LiteralPath $target).Length -gt 1000) {
      $ok = $true
      Write-Host ('Downloaded OK (' + (Get-Item -LiteralPath $target).Length + ' bytes)') -ForegroundColor Green
      break
    }
  } catch {
    Write-Host ('  failed: ' + $_.Exception.Message) -ForegroundColor Yellow
  }
}
if (-not $ok) {
  Write-Host ''
  Write-Host 'ERROR: could not download Addons-Fetcher.cmd from any source.' -ForegroundColor Red
  Write-Host 'Check your network/proxy settings and run this script again.' -ForegroundColor Yellow
  exit 1
}
$marker = '#PS' + 'START'
if ([IO.File]::ReadAllText($target, [Text.Encoding]::UTF8).IndexOf($marker) -lt 0) {
  Write-Host 'ERROR: the downloaded file does not look like the fetch script.' -ForegroundColor Red
  exit 1
}
Write-Host ''
Write-Host 'Addons-init: running Addons-Fetcher.cmd ...' -ForegroundColor Cyan
Write-Host ''
& cmd /c ('"' + $target + '"')
exit $LASTEXITCODE