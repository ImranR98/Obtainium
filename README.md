# ![Obtainium Icon](./assets/graphics/icon_small.png) ObtainX

## Extra features in ObtainX

ObtainX is a fork of Obtainium. These are the extra features you get in this fork:

- **Installer choice** – In Settings, you can choose how APKs are installed: **Stock** (default), **Shizuku**, or **Legacy**. Legacy mode lets you pick a custom installer (e.g. InstallerX, App Manager etc.) to handle the APK.

- **Smarter version handling** – If you have a **higher** version installed than what the remote reports (e.g. you're on a dev build or a newer release), ObtainX does **not** show "Update available." Only when the remote version is actually newer does it show an update. Same logic is used for "up to date" and "same build (different labels)" so you get accurate status chips.

- **Better tracking for track-only sources like APKMirror**

  - For track-only apps, Obtainium did not fetch the already installed app version and always showed "latest is installed," which was wrong. That is fixed here: the installed version is now read from the device when a package ID is available.
  - Added a new "Update" button to track-only app pages, tapping which opens the **specific update version page** (not just the app landing page).
  - Smarter version comparison so strings like `50.5.19` and `50.5.19-31 [PR]` are treated as the same.

- **Modernized app detail page** – The app page is no longer a single top-to-bottom text column. It is reorganized into clear sections with visual separation:
  - **Hero** – Back button and app info (icon, name, developer) on one row below the status bar.
  - **Version card** – Installed / Latest / Changelog as label-value rows, version status chip (e.g. "Same build (different labels)", "Update available"), and timestamps in `yyyy-mm-dd hh:mm` format.
  - **Details card** – Package, Source (as link), Last update check, Assets (as link to download). Certificate hash is included here. No separate "Download release asset" line; the Assets value is the download link.
  - **Categories card** – Category chips only, no duplicate labels.
  Cards use Material 3 surfaces and shadows so they read clearly in both light and dark themes.

- **UI polish** – Material 3 expressive buttons, SafeArea so the top row is not hidden by the status bar, and consistent link styling for Source, Assets, and Changelog.


## Screenshots
| <img src="./assets/screenshots/8.installer_choice.png" alt="Apps Page" /> | <img src="./assets/screenshots/9.material_buttons.png" alt="Dark Theme" /> | 
| ------------------------------------------------------ | ----------------------------------------------------------------------- | 

## Original Obtainium

Read the original Obtainium [README here](https://github.com/ImranR98/Obtainium/blob/main/README.md).
