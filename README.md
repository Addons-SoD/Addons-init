# Addons-init (WoW Forever)

Bootstrap script for [Addons-Fetcher](https://github.com/Addons-SoD/Addons-Fetcher),
branch **`wow-forever`**.

It downloads `Addons-Fetcher.cmd` from the `wow-forever` branch of the
Addons-Fetcher repository into the current directory and runs it, so a
completely empty `Interface` folder can be populated with a single
double-click.

## Target game

**World of Warcraft: Forever** ("魔兽世界：无限"), client folder `_forever_`,
product flavor `wowf`, addon interface **16001**. Forever runs the modern
Mainline UI family (the vast majority of the 12.1.5 addon API), **not**
Classic Era.

The script verifies the target by reading `.flavor.info` (`wowf`) next to the
`Interface` folder, with an Authenticode signature check of `Wow.exe` as
fallback.

## Usage

1. Copy `Addons-init.cmd` into your Forever client's `Interface` folder:
   `<WoW install dir>\_forever_\Interface`
2. Run it.
3. The fetcher is downloaded next to this script and started automatically;
   all addons are deployed into the `AddOns` subfolder
   (`Interface\AddOns` = the game's addon directory).

Download sources are tried in this order:

1. `api.github.com`
2. `raw.githubusercontent.com` (through the fastest probed channel)
3. `github.com/.../raw/...` redirect
4. `cdn.jsdelivr.net` (jsDelivr CDN mirror)

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

## Changes in the wow-forever branch

- Fetcher is pulled from `wow-forever` instead of `main`.
- Game check targets the Forever client (`Wow.exe`, `.flavor.info` = `wowf`).
- Version notice reads the `wow-forever` version of this script.
- Wording and README updated for Forever.

## Requirements

- Windows PowerShell 5.1+
- Network access to GitHub (or to the jsDelivr CDN as fallback)

## License

MIT - see [LICENSE](LICENSE).
