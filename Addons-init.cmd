@echo off
title Addons-init - Bootstrap for Addons-Fetcher
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$env:INIT_SELF='%~f0'; $env:INIT_DIR='%~dp0'; $c=[IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8); $m=([char]10).ToString()+'#PS'+'START'; $i=$c.IndexOf($m); if($i -lt 0){ Write-Host 'Script marker not found.'; exit 1 }; Invoke-Expression ($c.Substring($i+$m.Length))"
exit /b %ERRORLEVEL%
#PSSTART
# ============================================================================
#  Addons-init  v2
#  Bootstrap script: downloads the latest Addons-Fetcher.cmd from the
#  Addons-SoD/Addons-Fetcher repository into the current directory and
#  runs it. The fetcher then deploys all addons into this directory.
#  v2 changes (fixes slow/broken downloads of the fetcher itself):
#  * Uses curl.exe instead of Invoke-WebRequest and applies the same smart
#    channel idea as the fetcher:
#      - the Windows system proxy is detected and used automatically when
#        it is present (and faster),
#      - otherwise several raw.githubusercontent.com IPs (system DNS +
#        AliDNS 223.5.5.5) are probed in parallel and the fastest one is
#        used with --resolve.
#  * Fail-fast behaviour: 10s connect timeout + built-in retries instead of
#    one hanging 120s request, so a dead route is abandoned quickly and the
#    next source is tried.
#  * The target file is re-downloaded fresh (stale local copies are removed)
#    and validated by size + content marker.
#  Download sources are tried in order:
#    1. raw.githubusercontent.com  (through the fastest probed channel)
#    2. github.com/.../raw/... redirect (proxy if available)
#    3. cdn.jsdelivr.net (jsDelivr CDN mirror, plain direct)
# ============================================================================
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$ScriptDir   = ($env:INIT_DIR).TrimEnd('\')
$Owner       = 'Addons-SoD'
$Repo        = 'Addons-Fetcher'
$Branch      = 'main'
$FetcherName = 'Addons-Fetcher.cmd'
$RawHost     = 'raw.githubusercontent.com'

$rawUrl = 'https://raw.githubusercontent.com/' + $Owner + '/' + $Repo + '/' + $Branch + '/' + $FetcherName
$ghUrl  = 'https://github.com/' + $Owner + '/' + $Repo + '/raw/' + $Branch + '/' + $FetcherName
$jsUrl  = 'https://cdn.jsdelivr.net/gh/' + $Owner + '/' + $Repo + '@' + $Branch + '/' + $FetcherName
$target = Join-Path $ScriptDir $FetcherName
$work   = Join-Path $env:TEMP ('AddonInit_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $work | Out-Null

# ------------------------------- helpers ------------------------------------
function Get-SystemProxy{
  try{
    $ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
    if($ie.ProxyEnable -eq 1 -and $ie.ProxyServer){
      $s = [string]$ie.ProxyServer
      if($s -match '='){
        $m = [regex]::Match($s, '(?:https?|socks)=([^;]+)')
        if($m.Success){ $s = $m.Groups[1].Value.Trim() }
        if($s -match '^socks'){ return 'socks5h://' + ($s -replace '^socks\S*=','') }
      }
      return $s.Trim()
    }
  }catch{}
  return $null
}

function Get-RawIps{
  $list = New-Object System.Collections.Generic.List[string]
  try{
    [Net.Dns]::GetHostAddresses($RawHost) | ForEach-Object {
      if(-not $list.Contains($_.IPAddressToString)){ $list.Add($_.IPAddressToString) }
    }
  }catch{}
  try{
    $ali = & nslookup $RawHost 223.5.5.5 2>$null | Select-String -Pattern '\b(\d{1,3}\.){3}\d{1,3}\b' | ForEach-Object { $_.Matches[0].Value } | Where-Object { $_ -ne '223.5.5.5' }
    foreach($a in $ali){ if(-not $list.Contains($a)){ $list.Add($a) } }
  }catch{}
  return @($list)
}

function Get-CurlArgLine([string[]]$argArr){
  return (($argArr | ForEach-Object { if([string]$_ -match '[ "	]'){ '"' + ([string]$_ -replace '"','\"') + '"' } else { [string]$_ } }) -join ' ')
}

function Start-CurlProc([string[]]$argArr,[string]$outFile){
  $argLine = Get-CurlArgLine $argArr
  if($outFile){
    return Start-Process -FilePath 'curl.exe' -ArgumentList $argLine -PassThru -WindowStyle Hidden -RedirectStandardOutput $outFile -RedirectStandardError ($outFile + '.err')
  }
  return Start-Process -FilePath 'curl.exe' -ArgumentList $argLine -PassThru -WindowStyle Hidden
}

# Probe the candidate channels in parallel (8s each) against the real target
# file and return the fastest working one, or $null.
function Probe-Channels($candidates){
  if($null -eq $candidates -or @($candidates).Count -eq 0){ return $null }
  $procs = @()
  $i = 0
  foreach($ch in $candidates){
    $i++
    $outFile = Join-Path $work ('spd_' + $i + '.txt')
    $a = @('-s','-L','--max-time','8') + $ch.Args + @('-o','NUL','-w','%{speed_download}',$rawUrl)
    $p = Start-CurlProc $a $outFile
    $procs += @{ Ch = $ch; Proc = $p; Out = $outFile }
  }
  while(@($procs | Where-Object { -not $_.Proc.HasExited }).Count -gt 0){ Start-Sleep -Milliseconds 300 }
  Start-Sleep -Milliseconds 200
  $best = $null
  foreach($pr in $procs){
    $spd = 0.0
    try{
      if(Test-Path -LiteralPath $pr.Out){
        $t = [IO.File]::ReadAllText($pr.Out)
        if($t -match '^(\d+(\.\d+)?)'){ $spd = [double]$Matches[1] }
      }
    }catch{}
    if($spd -gt 0){
      Write-Host ('    ' + $pr.Ch.Id.PadRight(7) + ' ' + $pr.Ch.Label.PadRight(26) + ('{0,9:N0}' -f $spd) + ' B/s') -ForegroundColor Gray
      if($null -eq $best -or $spd -gt $best.Speed){ $best = @{ Id=$pr.Ch.Id; Speed=$spd; Args=$pr.Ch.Args; Label=$pr.Ch.Label } }
    } else {
      Write-Host ('    ' + $pr.Ch.Id.PadRight(7) + ' ' + $pr.Ch.Label.PadRight(26) + '    FAILED') -ForegroundColor DarkGray
    }
  }
  return $best
}

# ------------------------------ main flow -----------------------------------
Write-Host ''
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host '  Addons-init: fetching Addons-Fetcher.cmd' -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan

# ---- 1) pick the fastest channel (proxy vs direct multi-IP) ----
$sysProxy = Get-SystemProxy
Write-Host ('  System proxy : ' + $(if($sysProxy){ $sysProxy } else { '(none - using direct)' }))
$channel = $null
$candidates = @()
$idx = 0
if($sysProxy){ $candidates += @{ Id='PROXY'; Args=@('--proxy',$sysProxy); Label='proxy ' + $sysProxy } }
foreach($ip in (Get-RawIps)){
  $idx++
  $candidates += @{ Id=('IP'+$idx); Args=@('--resolve',($RawHost + ':443:' + $ip)); Label=$ip }
}
if($candidates.Count -gt 0){
  Write-Host '  Probing channels (8s each, parallel):' -ForegroundColor Gray
  $channel = Probe-Channels $candidates
  if($channel){
    if($channel.Id -eq 'PROXY'){
      Write-Host ('  -> Using system proxy: ' + $sysProxy + ' (' + ('{0:N0}' -f $channel.Speed) + ' B/s)') -ForegroundColor Green
    } else {
      $ip = ($channel.Args[1] -split ':')[-1]
      Write-Host ('  -> Using direct IP: ' + $ip + ' (' + ('{0:N0}' -f $channel.Speed) + ' B/s)') -ForegroundColor Green
    }
  } else {
    Write-Host '  All channels failed - using the default direct connection.' -ForegroundColor Yellow
  }
}

# ---- 2) download (fail-fast: 10s connect timeout, retries, fresh target) ----
function Invoke-Download($url,[string[]]$extra){
  if(Test-Path -LiteralPath $target){ Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue }
  $a = @('-s','-L','--fail','--retry','3','--retry-delay','1','--connect-timeout','10','--max-time','90','-o',$target)
  if($extra){ $a += $extra }
  $a += $url
  & curl.exe @a
  return ($LASTEXITCODE -eq 0)
}

$ok = $false
# 1) raw.githubusercontent.com through the fastest probed channel
if($channel){ $ok = Invoke-Download $rawUrl $channel.Args }
# 2) raw through plain DNS (no channel arguments)
if(-not $ok){ $ok = Invoke-Download $rawUrl @() }
# 3) github.com raw redirect (proxy if available)
if(-not $ok){
  Write-Host '  Falling back to github.com raw redirect ...' -ForegroundColor Gray
  $extra = @()
  if($sysProxy){ $extra = @('--proxy',$sysProxy) }
  $ok = Invoke-Download $ghUrl $extra
}
# 4) jsDelivr CDN mirror (plain direct - usually reachable even when GitHub is not)
if(-not $ok){
  Write-Host '  Falling back to cdn.jsdelivr.net ...' -ForegroundColor Gray
  $ok = Invoke-Download $jsUrl @()
}

if($ok){
  $len = (Get-Item -LiteralPath $target).Length
  Write-Host ('Downloaded OK (' + $len + ' bytes)') -ForegroundColor Green
} else {
  Write-Host ''
  Write-Host 'ERROR: could not download Addons-Fetcher.cmd from any source.' -ForegroundColor Red
  Write-Host 'Check your network/proxy settings and run this script again.' -ForegroundColor Yellow
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  exit 1
}

# ---- 3) validate + run ----
if((Get-Item -LiteralPath $target).Length -le 1000){
  Write-Host 'ERROR: downloaded file is too small - aborting.' -ForegroundColor Red
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  exit 1
}
$marker = '#PS' + 'START'
if([IO.File]::ReadAllText($target, [Text.Encoding]::UTF8).IndexOf($marker) -lt 0){
  Write-Host 'ERROR: the downloaded file does not look like the fetch script.' -ForegroundColor Red
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  exit 1
}
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host 'Addons-init: running Addons-Fetcher.cmd ...' -ForegroundColor Cyan
Write-Host ''
& cmd /c ('"' + $target + '"')
exit $LASTEXITCODE
