@echo off
title Addons-init - Bootstrap for Addons-Fetcher
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$env:INIT_SELF='%~f0'; $env:INIT_DIR='%~dp0'; $c=[IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8); $m=([char]10).ToString()+'#PS'+'START'; $i=$c.IndexOf($m); if($i -lt 0){ Write-Host 'Script marker not found.'; exit 1 }; Invoke-Expression ($c.Substring($i+$m.Length))"
exit /b %ERRORLEVEL%
#PSSTART
# ============================================================================
#  Addons-init  v3
#  Bootstrap script: downloads the latest Addons-Fetcher.cmd from the
#  Addons-SoD/Addons-Fetcher repository into the current directory and
#  runs it. The fetcher then deploys all addons into this directory.
#  v3 changes:
#  * Console output is kept within 80 columns (long lines are truncated).
#  * QuickEdit is disabled and the cursor is hidden while the script runs,
#    so clicking the console window can no longer pause the script; the
#    console is restored before exiting.
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
# Console width is kept at 80 columns (best compatibility); long lines are
# truncated with '...'.
$ConWidth = 80
$HLine = '=' * $ConWidth

function Truncate-Text([string]$s,[int]$maxLen){
  if($s.Length -gt $maxLen){
    if($maxLen -le 3){ return $s.Substring(0, [Math]::Min($maxLen, $s.Length)) }
    return $s.Substring(0, $maxLen - 3) + '...'
  }
  return $s
}

# Animated spinner character shown while waiting (probing / downloading).
$script:SpinIdx = 0
function Get-SpinChar{
  $script:SpinIdx = ($script:SpinIdx + 1) % 4
  return ('-','\','|','/')[$script:SpinIdx]
}

# Disable QuickEdit (clicking the console pauses the script in select mode)
# and hide the cursor while running.
function Init-ConsoleMode{
  try{
    if(-not ('AddonsConsoleHelper' -as [type])){
      $src = @'
using System;
using System.Runtime.InteropServices;
public static class AddonsConsoleHelper {
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern IntPtr GetStdHandle(int nStdHandle);
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern bool SetConsoleCursorInfo(IntPtr hConsoleOutput, ref CONSOLE_CURSOR_INFO lpConsoleCursorInfo);
  [StructLayout(LayoutKind.Sequential)]
  public struct CONSOLE_CURSOR_INFO { public uint dwSize; public bool bVisible; }
}
'@
      Add-Type -TypeDefinition $src
    }
    $in  = [AddonsConsoleHelper]::GetStdHandle(-10)
    $out = [AddonsConsoleHelper]::GetStdHandle(-11)
    $mode = [uint32]0
    if([AddonsConsoleHelper]::GetConsoleMode($in, [ref]$mode)){
      $mode = $mode -band (-bnot 0x0040) -band (-bnot 0x0020)
      [void][AddonsConsoleHelper]::SetConsoleMode($in, $mode)
    }
    $cci = New-Object AddonsConsoleHelper+CONSOLE_CURSOR_INFO
    $cci.dwSize = 1
    $cci.bVisible = $false
    [void][AddonsConsoleHelper]::SetConsoleCursorInfo($out, [ref]$cci)
  }catch{}
}

# Restore QuickEdit + the cursor before exiting (also before Read-Host).
function Restore-ConsoleMode{
  try{
    if(('AddonsConsoleHelper' -as [type])){
      $in  = [AddonsConsoleHelper]::GetStdHandle(-10)
      $out = [AddonsConsoleHelper]::GetStdHandle(-11)
      $mode = [uint32]0
      if([AddonsConsoleHelper]::GetConsoleMode($in, [ref]$mode)){
        $mode = $mode -bor 0x0040 -bor 0x0020
        [void][AddonsConsoleHelper]::SetConsoleMode($in, $mode)
      }
      $cci = New-Object AddonsConsoleHelper+CONSOLE_CURSOR_INFO
      $cci.dwSize = 20
      $cci.bVisible = $true
      [void][AddonsConsoleHelper]::SetConsoleCursorInfo($out, [ref]$cci)
    }
  }catch{}
}

# True when the parent directory looks like the game folder: WowClassic.exe
# exists next to it AND its Authenticode signature comes from Blizzard.
function Test-GameFolder{
  try{
    $parent = Split-Path -Parent $ScriptDir
    $exe = Join-Path $parent 'WowClassic.exe'
    if(Test-Path -LiteralPath $exe){
      $sig = Get-AuthenticodeSignature -LiteralPath $exe
      if($sig.Status -eq 'Valid' -and $null -ne $sig.SignerCertificate){
        $who = $sig.SignerCertificate.Subject + ' ' + $sig.SignerCertificate.Issuer
        if($who -match 'Blizzard'){ return $true }
      }
    }
  }catch{}
  return $false
}

# Download with a fail-fast curl (15s connect timeout, retries, fresh
# target); curl runs as a background process while the main thread shows
# a spinner. Optional extra curl args and extra headers.
function Invoke-Download($url,[string[]]$extra,[string]$label,[string[]]$headers){
  if(Test-Path -LiteralPath $target){ Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue }
  $a = @('-s','-L','--fail','--retry','3','--retry-delay','1','--connect-timeout','15','--max-time','90')
  if($headers){ $a += $headers }
  $a += @('-o',$target)
  if($extra){ $a += $extra }
  $a += $url
  $argLine = Get-CurlArgLine $a
  $p = Start-Process -FilePath 'curl.exe' -ArgumentList $argLine -PassThru -WindowStyle Hidden
  while(-not $p.HasExited){
    Write-Host ("`r  " + (Get-SpinChar) + ' downloading ' + $label + ' ...') -NoNewline
    Start-Sleep -Milliseconds 200
  }
  Write-Host ("`r" + (' ' * $ConWidth)) -NoNewline
  Write-Host ''
  return ($p.ExitCode -eq 0)
}

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
  while(@($procs | Where-Object { -not $_.Proc.HasExited }).Count -gt 0){
    Write-Host ("`r  " + (Get-SpinChar) + ' probing channels ...') -NoNewline
    Start-Sleep -Milliseconds 300
  }
  Write-Host ("`r" + (' ' * $ConWidth)) -NoNewline
  Write-Host ''
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
      Write-Host (Truncate-Text ('    ' + $pr.Ch.Id.PadRight(7) + ' ' + $pr.Ch.Label.PadRight(22) + ('{0,9:N0}' -f $spd) + ' B/s') $ConWidth) -ForegroundColor Gray
      if($null -eq $best -or $spd -gt $best.Speed){ $best = @{ Id=$pr.Ch.Id; Speed=$spd; Args=$pr.Ch.Args; Label=$pr.Ch.Label } }
    } else {
      Write-Host (Truncate-Text ('    ' + $pr.Ch.Id.PadRight(7) + ' ' + $pr.Ch.Label.PadRight(22) + '    FAILED') $ConWidth) -ForegroundColor DarkGray
    }
  }
  return $best
}

# ------------------------------ main flow -----------------------------------
Init-ConsoleMode
Write-Host ''
Write-Host $HLine -ForegroundColor Cyan
Write-Host '  Addons-init: fetching Addons-Fetcher.cmd' -ForegroundColor Cyan
Write-Host $HLine -ForegroundColor Cyan

# Warn (in English) when the script does not run from the game's Interface
# folder: the addons will be deployed next to this script instead.
if(-not (Test-GameFolder)){
  Write-Host ''
  Write-Host '  WARNING: WowClassic.exe was not found in the parent folder,' -ForegroundColor Yellow
  Write-Host '  or its signature is not from Blizzard. You are probably' -ForegroundColor Yellow
  Write-Host '  NOT running this script from the game''s Interface folder.' -ForegroundColor Yellow
  Write-Host '  The addons will be downloaded next to this script. After' -ForegroundColor Yellow
  Write-Host '  the download finishes, please manually copy the ''AddOns''' -ForegroundColor Yellow
  Write-Host '  folder into your game''s Interface directory.' -ForegroundColor Yellow
  Write-Host ''
}

# ---- download: try the fast api.github.com route first ----
# api.github.com (Azure) is on the same fast route as codeload.github.com,
# while raw.githubusercontent.com (Fastly) is often blocked/throttled - so
# api is tried before any probing, and probing only runs when api fails.
$sysProxy = Get-SystemProxy
Write-Host ('  System proxy : ' + $(if($sysProxy){ $sysProxy } else { '(none - using direct)' }))
$ok = $false
$apiUrl  = 'https://api.github.com/repos/' + $Owner + '/' + $Repo + '/contents/' + $FetcherName
$apiExtra = @()
if($sysProxy){ $apiExtra = @('--proxy',$sysProxy) }
if(Invoke-Download $apiUrl $apiExtra 'Addons-Fetcher.cmd (api.github.com)' @('-H','Accept: application/vnd.github.raw')){
  $ok = $true
}

if(-not $ok){
  # ---- channel probing (proxy vs direct multi-IP) ----
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
  # 1) raw.githubusercontent.com through the fastest probed channel
  if($channel){ $ok = Invoke-Download $rawUrl $channel.Args 'Addons-Fetcher.cmd' }
  # 2) raw through plain DNS (no channel arguments)
  if(-not $ok){ $ok = Invoke-Download $rawUrl @() 'Addons-Fetcher.cmd (plain)' }
  # 3) github.com raw redirect (proxy if available)
  if(-not $ok){
    Write-Host '  Falling back to github.com raw redirect ...' -ForegroundColor Gray
    $extra = @()
    if($sysProxy){ $extra = @('--proxy',$sysProxy) }
    $ok = Invoke-Download $ghUrl $extra 'Addons-Fetcher.cmd (github redirect)'
  }
  # 4) jsDelivr CDN mirror (plain direct - usually reachable even when GitHub is not)
  if(-not $ok){
    Write-Host '  Falling back to cdn.jsdelivr.net ...' -ForegroundColor Gray
    $ok = Invoke-Download $jsUrl @() 'Addons-Fetcher.cmd (jsdelivr)'
  }
}

if($ok){
  $len = (Get-Item -LiteralPath $target).Length
  Write-Host ('Downloaded OK (' + $len + ' bytes)') -ForegroundColor Green
} else {
  Write-Host ''
  Write-Host 'ERROR: could not download Addons-Fetcher.cmd from any source.' -ForegroundColor Red
  Write-Host 'Check your network/proxy settings and run this script again.' -ForegroundColor Yellow
  Restore-ConsoleMode
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  exit 1
}

# ---- 3) validate + run ----
if((Get-Item -LiteralPath $target).Length -le 1000){
  Write-Host 'ERROR: downloaded file is too small - aborting.' -ForegroundColor Red
  Restore-ConsoleMode
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  exit 1
}
$marker = '#PS' + 'START'
if([IO.File]::ReadAllText($target, [Text.Encoding]::UTF8).IndexOf($marker) -lt 0){
  Write-Host 'ERROR: the downloaded file does not look like the fetch script.' -ForegroundColor Red
  Restore-ConsoleMode
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  exit 1
}
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host 'Addons-init: running Addons-Fetcher.cmd ...' -ForegroundColor Cyan
Write-Host ''
Restore-ConsoleMode
& cmd /c ('"' + $target + '"')
exit $LASTEXITCODE
