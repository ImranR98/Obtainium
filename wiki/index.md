# ![Obtainium Icon](https://raw.githubusercontent.com/ImranR98/Obtainium/main/assets/graphics/icon_small.png) Obtainium Wiki

---

[![Ceasefire Now](https://badge.techforpalestine.org/default)](https://techforpalestine.org/learn-more)

Get Android app updates straight from the source.

Obtainium's core goal is to automate the process of downloading and installing Android app updates directly from their "source" websites (sites where app files are available for direct download). This process needs automation since users may not be willing or able to rely on an app store to update a given app, but Android apps (unlike PC apps) usually assume they will be updated externally by an app store and therefore don't include a built-in self-update function.

While this concept is simple, the wide variety of supported sources, user preferences, and APK naming, versioning, and distribution methods make things more complicated. This Wiki explains the various app sources and settings available in Obtainium. It is not comprehensive and may not be fully up to date.

More info

- [AppVerifier](https://github.com/soupslurpr/AppVerifier) - App verification tool (recommended, integrates with Obtainium)
- [apps.obtainium.imranr.dev](https://apps.obtainium.imranr.dev/) - Crowdsourced app configurations
- [Side Of Burritos - You should use this instead of F-Droid | How to use app RSS feed](https://youtu.be/FFz57zNR_M0) - Original motivation for this app

Currently supported App sources:

- Open Source - General:
    - [GitHub](https://github.com/)
    - [GitLab](https://gitlab.com/)
    - [Forgejo](https://forgejo.org/) ([Codeberg](https://codeberg.org/))
    - [F-Droid](https://f-droid.org/)
    - Third Party F-Droid Repos
    - [IzzyOnDroid](https://android.izzysoft.de/)
    - [SourceHut](https://git.sr.ht/)
- Other - General:
    - [APKPure](https://apkpure.net/)
    - [Aptoide](https://aptoide.com/)
    - [Uptodown](https://uptodown.com/)
    - [Huawei AppGallery](https://appgallery.huawei.com/)
    - [Tencent App Store](https://sj.qq.com/)
    - Jenkins Jobs
    - [APKMirror](https://apkmirror.com/) (Track-Only)
- Open Source - App-Specific:
    - [VLC](https://videolan.org/)
- Other - App-Specific:
    - [WhatsApp](https://whatsapp.com)
    - [Telegram App](https://telegram.org)
    - [Neutron Code](https://neutroncode.com)
- Direct APK Link
- "HTML" (Fallback): Any other URL that returns an HTML page with links to APK files

## Finding App Configurations

You can find crowdsourced app configurations at [apps.obtainium.imranr.dev](https://apps.obtainium.imranr.dev).

If you can't find the configuration for an app you want, feel free to leave a request on the [discussions page](https://github.com/ImranR98/apps.obtainium.imranr.dev/discussions/new?category=app-requests).

Or, contribute some configurations to the website by creating a PR at [this repo](https://github.com/ImranR98/apps.obtainium.imranr.dev).

## Installation

[<img src="https://github.com/machiav3lli/oandbackupx/raw/034b226cea5c1b30eb4f6a6f313e4dadcbb0ece4/badge_github.png"
    alt="Get it on GitHub">](https://github.com/ImranR98/Obtainium/releases)
[<img src="https://gitlab.com/IzzyOnDroid/repo/-/raw/master/assets/IzzyOnDroid.png"
     alt="Get it on IzzyOnDroid">](https://apt.izzysoft.de/fdroid/index/apk/dev.imranr.obtainium)
[<img src="https://fdroid.gitlab.io/artwork/badge/get-it-on.png"
    alt="Get it on F-Droid">](https://f-droid.org/packages/dev.imranr.obtainium.fdroid/)
     
Verification info:

- Package ID: `dev.imranr.obtainium`
- SHA-256 Hash of Signing Certificate: `B3:53:60:1F:6A:1D:5F:D6:60:3A:E2:F5:0B:E8:0C:F3:01:36:7B:86:B6:AB:8B:1F:66:24:3D:A9:6C:D5:73:62`
  - Note: The above signature is also valid for the F-Droid flavour of Obtainium, thanks to [reproducible builds](https://f-droid.org/docs/Reproducible_Builds/).
- [PGP Public Key](https://keyserver.ubuntu.com/pks/lookup?search=contact%40imranr.dev&fingerprint=on&op=index) (to verify APK hashes)

## Limitations
- For some sources, data is gathered using Web scraping and can easily break due to changes in website design. In such cases, more reliable methods may be unavailable.
