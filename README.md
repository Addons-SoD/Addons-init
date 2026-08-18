# Addons-init

Bootstrap script for [Addons-Fetcher](https://github.com/Addons-SoD/Addons-Fetcher).

It downloads the latest `Addons-Fetcher.cmd` from the
[Addons-SoD/Addons-Fetcher](https://github.com/Addons-SoD/Addons-Fetcher)
repository into the current directory and runs it, so a completely empty addon
folder can be populated with a single double-click.

## Usage

1. Copy `Addons-init.cmd` into your target addon directory:
   `<WoW install dir>\_classic_era_\Interface\AddOns`
2. Run it.
3. The fetcher is downloaded next to this script and started automatically;
   all addons are deployed into the same directory.

Download sources are tried in this order:

1. `raw.githubusercontent.com`
2. `github.com/.../raw/...` redirect
3. `cdn.jsdelivr.net` (jsDelivr CDN mirror)

## Requirements

- Windows PowerShell 5.1+
- Network access to GitHub (or to the jsDelivr CDN as fallback)

## License

MIT - see [LICENSE](LICENSE).