# Addons-init

Bootstrap script for [Addons-Fetcher](https://github.com/Addons-SoD/Addons-Fetcher).

It downloads the latest `Addons-Fetcher.cmd` from the
[Addons-SoD/Addons-Fetcher](https://github.com/Addons-SoD/Addons-Fetcher)
repository into the current directory and runs it, so a completely empty
`Interface` folder can be populated with a single double-click.

## Usage

1. Copy `Addons-init.cmd` into your `Interface` folder:
   `<WoW install dir>\_classic_era_\Interface`
2. Run it.
3. The fetcher is downloaded next to this script and started automatically;
   all addons are deployed into the `Addons` subfolder
   (`Interface\Addons` = the game's addon directory).

Download sources are tried in this order:

1. `raw.githubusercontent.com`
2. `github.com/.../raw/...` redirect
3. `cdn.jsdelivr.net` (jsDelivr CDN mirror)

## Smart downloads (v2)

Slow or broken fetcher downloads are usually caused by a bad direct route
to GitHub (the DNS-provided IP may be unreachable). v2 fixes this the same
way the fetcher does:

- Uses `curl.exe` with **fail-fast** behaviour (10s connect timeout +
  built-in retries) instead of one hanging 120s request.
- **Channel probing**: if a Windows system proxy is present it is used
  automatically; otherwise several `raw.githubusercontent.com` IPs (system
  DNS + AliDNS) are probed in parallel and the fastest reachable one is
  used (`--resolve`). A dead default DNS node no longer blocks the download.

## Requirements

- Windows PowerShell 5.1+
- Network access to GitHub (or to the jsDelivr CDN as fallback)

## License

MIT - see [LICENSE](LICENSE).
