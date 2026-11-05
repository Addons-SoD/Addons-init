# Addons-init-Forever

Bootstrap script for [Addons-Fetcher-Forever](https://github.com/Addons-SoD/Addons-Fetcher-Forever),
the World of Warcraft: Forever flavour of the Addons-SoD one-click deployer.

It downloads `Addons-Fetcher.cmd` from `Addons-SoD/Addons-Fetcher-Forever`
into the current directory and runs it, so a completely empty `Interface`
folder can be populated with a single double-click.

## Why a separate repository

The Classic Era / Season of Discovery tooling stays in
[Addons-SoD/Addons-init](https://github.com/Addons-SoD/Addons-init) and
[Addons-SoD/Addons-Fetcher](https://github.com/Addons-SoD/Addons-Fetcher)
and is **not modified** by this port. The Forever port mirrors the naming of
the existing `*-SoD` addon repositories: every Forever artefact lives in a
`*-Forever` repository. Deploying for Forever therefore can never change the
SoD addon set, and vice versa.

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

Download sources for the fetcher are tried in this order, all inside
`Addons-SoD/Addons-Fetcher-Forever`:

1. `api.github.com` (`?ref=main`)
2. `raw.githubusercontent.com`
3. `github.com/.../raw/...` redirect
4. `cdn.jsdelivr.net` (jsDelivr CDN mirror)

## Version check

Before fetching, the script compares its own `$ScriptVersion` with the one in
`Addons-SoD/Addons-init-Forever` and shows a magenta notice when a newer
version is available. The notice links to the raw file of **this same
repository** - it can never point at the Classic Era script.

## Smart downloads

Slow or broken fetcher downloads are usually caused by a bad direct route
to GitHub (the DNS-provided IP may be unreachable):

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
