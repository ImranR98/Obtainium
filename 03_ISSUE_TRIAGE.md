# 03_ISSUE_TRIAGE.md — Obtainium Issue Triage

## Triage Summary
- **Total open issues**: ~90+ (as of May 2026)
- **Bug**: ~50 open
- **Enhancement**: ~30 open
- **Source-specific**: Many (third-party scraping sources are inherently fragile)
- **Security-relevant**: 5 identified

---

## Security-Relevant Issues

| # | Title | Type | Priority | Notes |
|---|---|---|---|---|
| 2916 | Certificate pinning for secure connections | enhancement | MEDIUM | No TLS pinning — all sources vulnerable to MITM |
| 2922 | signing certificate hash | question | MEDIUM | Hash storage/verification for APK signing certs |
| 1482 | Resend pending update notifications after reboot | enhancement | MEDIUM | Notification reliability/security |
| 462 | Option to run APK through VirusTotal | enhancement | MEDIUM | User-requested APK scanning integration |
| 651 | Verify Google Play APKs from 3rd party sources are signed by Google | enhancement | MEDIUM | APK signature verification for third-party sources |
| 1458 | Expired certificate | bug | HIGH | Certificate validation issue affecting downloads |

---

## Critical / High Priority Bugs

| # | Title | Source | Risk | Notes |
|---|---|---|---|---|
| 2848 | Crash NullPointerException scrolling Android 16/One UI 8.0 | UI | HIGH | Platform-specific regression |
| 2909 | Cannot restore Signal backup from Playstore driven Device | install | HIGH | Cross-install signing/ID mismatch |
| 2860 | PathNotFoundException when importing from sources | import | HIGH | File system access edge case |
| 2868 | APK not found in ZIP with subfolder | archive | HIGH | Archive extraction bug |
| 2850 | Version code errors prevent updates | version-parse | HIGH | Version parsing regression |
| 2808 | Can't install some apps from APTOIDE | source-specific | HIGH | Aptoide source breaks |
| 2816 | HTML sources fail to extract links correctly in edge cases | source-specific | HIGH | HTML scraping fragility |
| 2830 | F-Droid APK v1.4.0 release section contains v1.3.4 | build | HIGH | Wrong binary shipped |
| 2851 | v1.4.0 stopped support for Android 7.0 | compat | HIGH | Regression breaking old Android |
| 2747 | Import extra JSON triggers false "app is newer" error | import | HIGH | Version comparison bug on import |
| 2908 | Immediate crash after opening on 32-bit device versions 1.2.9+ | compat | HIGH | 32-bit regression |
| 2884 | 1.4.2 unusable on AndroidTV | compat | HIGH | TV-specific regression |
| 2879 | New TV UI removes ability to import/export backups on TV | TV/UI | HIGH | Regression for TV users |
| 2806 | Significant startup delay & crash unless cache cleared (v1.3.4) | perf | HIGH | Memory/initialization bug |
| 2849 | F-Droid reproducible build failed | build | MEDIUM | Build reproducibility issue |

---

## Bug Breakdown by Category

### Crashes / NullPointer
- #2848 — NPE scrolling Android 16 / One UI 8.0
- #2889 — VC SIGTRAP_BRKPT caused by webview

### Source Scraping (Fragility — Expected)
Most bugs are from scraping third-party sites:
- #2921 Error 403 from rockmods
- #2751 Uptodown Certificate error
- #2813 HTML sources link extraction edge cases
- #2752 Uptodown certificate error
- #2335 Error 403 APKMirror (Spotify)
- #2732 GitLab releases no longer found
- #2913 SourceHut fail
- #2925 F-Droid not seeing latest OsmAnd release

### Version Parsing
- #2850 Version code errors prevent updates
- #2926 List pseudo-version & version (enhancement to show)
- #2868 APK not found in ZIP with subfolder
- #2826 Pseudo-version display issue

### Import/Export
- #2860 PathNotFoundException on import from sources
- #2879 TV UI removes import/export on TV
- #2877 Scrolling on app info stops short
- #2747 Import JSON triggers false "app is newer" error
- #2234 Language setting not reliable after restart

### UI / Display
- #2877 Scrolling on app info stops short
- #2672 Chinese font rendering issue
- #2771 Black bar in landscape on front camera
- #2769 Glitched UI in Waydroid
- #2909 Signal backup restore fails

### Installation / Shizuku
- #2909 Signal backup restore — Playstore vs Obtainium signing
- #2878 type 'bool' not subtype of 'String' (add app bug)
- #2172 Shizuku + Google Play source doesn't show in Android Auto
- #2822 Adding 2 apps from same repo impossible

### Network / HTTP
- #2553 "No route to host"
- #1885 Failed Host Lookup
- #2694 403 error with GitHub PAT + member rights
- #1458 Expired certificate (bug)

---

## Enhancements by Category

### New Sources
- #2930 Support 7z release assets
- #2902 Support ZapStore
- #2821 Add pdalife.com
- #2191 Add LeeAPK / APKVision (closed)
- #2859 OpenAPK support

### Source Improvements
- #2895 Include prerelease automatically
- #2929 Apply regex filter to "Download release asset"
- #2927 Filtering by categories
- #2906 Centralize logging
- #2457 Apply version regex before following intermediate links
- #2685 Request more pages from GitHub if first page has no releases

### UI/UX
- #2853 Slider for max parallel downloads
- #2801 Add latest version number to Apps tab
- #2857 Some apps require extra "update" tap
- #2813 Keep WebView on back — navigate history

### Background / Notification
- #1482 Resend pending notifications after reboot
- #2837 Enable memory tagging (closed)
- #2838 Utilize hardened_malloc (closed)
- #2752 Ability to disable older app notifications
- #2319 Disable background updates when charge is low

### Installer / System
- #517 App Manager Installer integration request
- #1321 Can't install apps on HyperOS/MIUI
- #2825 Target API too low for background updates
- #2844 Allow reordering installers (dhizuku/shizuku/sui)
- #2853 Max parallel downloads slider
- #2900 Third-party download managers
- #2858 Hardened memory (closed)

### Security
- #2916 Certificate pinning
- #462 VirusTotal integration
- #651 Verify Google Play APKs from third parties
- #2905 WebDAV support
- #2904 Google Play availability (closed — won't add)

### Data / Import
- #2611 Suggestion app
- #2359 CHANGELOG.md support
- #2870 RuStore search

---

## Open PRs (Pending Merge)

| # | Title | Author | Status |
|---|---|---|---|
| 2928 | Migrate from WillPopScope to PopScope | sinoate | OPEN |
| 2923 | Disable changelog rendering as Markdown for RuStore | Psychosoc1al | OPEN |
| 2912 | i18n: Update zh-Hant-TW.json | abc0922001 | OPEN |
| 2906 | Centralize logging | dordzhiev | OPEN |
| 2899 | Fix czech translation | vojta-horanek | OPEN |
| 2893 | Update nl.json | ojppe | OPEN |
| 2890 | i18n: update pl.json | krvstek | OPEN |

---

## Issue Volume Trend (Recent Months)

| Month | Open Issues (approx) | Trends |
|---|---|---|
| May 2026 | ~90 | Current |
| Apr 2026 | ~85 | High volume, many regressions |
| Mar 2026 | ~60 | Moderate |
| Jan 2026 | ~50 | Decreasing |

**Note**: Issue #2850 (version code errors), #2851 (Android 7 regression), and #2848 (Android 16 crash) suggest a quality regression around v1.4.x releases.

---

## Recommended Triage Actions

### Immediately
1. **#2848** — NPE on Android 16 / One UI 8 — high crash count, needs platform-specific fix
2. **#2850** — Version code errors — blocks updates for affected apps
3. **#2860** — PathNotFoundException on import — data loss risk

### Short Term
4. **#2816** — HTML source extraction edge cases — scrapers break frequently
5. **#2921** — RockMods 403 — source-specific API change
6. **#2732** — GitLab releases not found — API change likely

### Security (No Certificate Pinning)
7. **#2916** — Needs deliberate design decision: pinning means maintenance burden for rotating certs
8. **#651** — APK signature verification — would increase trust in third-party sources
