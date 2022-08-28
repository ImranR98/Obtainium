# ![Obtainium Icon](./android/app/src/main/res/drawable/ic_notification.png) Obtainium

Get Android App Updates Directly From the Source.

Obtainium allows you to install and update Open-Source Apps directly from their releases pages, and receive notifications when new releases are made available.

Motivation: [Side Of Burritos - You should use this instead of F-Droid | How to use app RSS feed](https://youtu.be/FFz57zNR_M0)

Currently supported App sources:
- [GitHub](https://github.com/)
- [GitLab](https://gitlab.com/)
- [F-Droid](https://f-droid.org/)
- [Mullvad](https://mullvad.net/en/)
- [Signal](https://signal.org/)

## Limitations
- App installs are assumed to have succeeded; failures and cancelled installs cannot be detected.
- Auto (unattended) updates are unsupported due to a lack of any capable Flutter plugin.
- For some sources, data is gathered using Web scraping and can easily break due to changes in website design. In such cases, more reliable methods are either unavailable (e.g. Mullvad), insufficient (e.g. GitHub RSS) or subject to rate limits (e.g. GitHub API).

## Screenshots

| <img src="./screenshots/1.apps.png" alt="Apps Page" /> | <img src="./screenshots/2.dark_theme.png" alt="Dark Theme" />           | <img src="./screenshots/3.material_you.png" alt="Material You" />    |
| ------------------------------------------------------ | ----------------------------------------------------------------------- | -------------------------------------------------------------------- |
| <img src="./screenshots/4.app.png" alt="App Page" />   | <img src="./screenshots/5.apk_picker.png" alt="Multiple APK Support" /> | <img src="./screenshots/6.apk_install.png" alt="App Installation" /> |
