---
title: App Sources
description: Information specific to certain sources
---

# App Sources

The way that an app is added, checked for updates, and installs will vary depending on source and the settings configured for that app by the user.

The following options are available for all apps regardless of source:

- Track-Only: Enabling this toggle allows you to receive update notifications for apps without attempting to actually download their APKs. This is useful to track updates for apps where no APKs are available, or where they cannot easily be extracted by Obtainium. Some sources are exclusively track-only - for example [ApkMirror](#apkmirror). Note that [version detection](app_tracking.md/#version-detection) will not work for any apps added as track-only.
- Version Detection: See the section on [version detection](app_tracking.md/#version-detection).
- Filter APKs by Regular Expression: When more than one APK is available for an app release, the user is prompted to pick one manually. Aside from being inconvenient, this means the app will not be updated silently in the background even when doing so would have otherwise been possible. This option lets the user specify a regular expression that can be used to filter out APK that don't match it (ideally down to one option).
- Attempt to filter APKs by CPU architecture if possible: This toggle will tell Obtainium to automatically filter out any APKs that don't appear to be compatible with the user's device. The logic used to do this is very simple and is based on the APK filename, so it is not always reliable and the user may still need to do their own filtering in many cases.
- App Name: This allows the user to specify their own name for the app instead of using the one Obtainium extracts.
- Exempt from background updates: This toggle will prevent the app from being updated silently in the background even if background updates are enabled and this app would otherwise have fulfilled all criteria to be updated in the background.
- Skip update notifications: This toggle tells Obtainium to avoid notifying the user that this app has an update available or that it was updated in the background.

Aside from those, each app has additional source-specific options. Most of those are self-explanatory and may be updated frequently, so they are not covered in this Wiki. However, some sources do have more unique behaviours that need more explanation, and these are covered below.

## GitHub

GitHub puts a cap on the number of API requests you can make in a given period of time. Since Obtainium uses the GitHub API to grab release info, you may run into a "rate limit" error if you have more than a few dozen GitHub apps. You can get around this by following [these instructions](settings.md/#__tabbed_1_1).

GitHub also allows developers to host multiple releases of their app. This usually means older versions of the same app, but may also include pre-releases, variants, etc. - so Obtainium provides various filters that let you navigate this and grab the exact releases you are interested in.

## GitLab

GitLab releases sometimes contain APKs that are attached in non-standard ways, such that Obtainium cannot get to them easily. To fix this, follow [these instructions](settings.md/#__tabbed_1_2).

Just like GitHub, GitLab also allows developers to host older releases of the same app, so additional options are provided as appropriate.

## F-Droid Third Party Repo

Unlike with most other sources, F-Droid repos contain info about multiple apps all under the same URL. This means that, in addition to the repo URL, you must provide the name or ID of the app you want separately. If you're not sure what apps are available in a given repo, you can use the "Search Source" button on the [Import/Export page](ui_overview.md/#importexport-page) to find out.

Note that Obtainium cannot automatically tell that a given URL points to a third-party F-Droid repo. This means that by default, adding a third-party F-Droid repo to Obtainium will result in the incorrect use of the [HTML source](#html) (a fallback source Obtainium uses for any URL it does not recognize). You must manually select "F-Droid Third Party Repo" from the "Override Source" dropdown to get around this.

## APKMirror

APKMirror is a "Track-Only" source. This means that while you can add an APKMirror URL to Obtainium for update notifications, you will not be able to actually download and install the app. This is because the maintainers of APKMirror do not allow it (see [issue #44](https://github.com/ImranR98/Obtainium/issues/44)).

## HTML

The 'HTML' source is a fallback option for any app sources that are not explicitly supported by Obtainium. Because of its flexibility, it is also a way of supporting niche, less popular sources without bloating the app.

The HTML Source works in this way:

1. It sends a request to the source URL provided by the user, and parses the response as HTML. It then looks for links on the page.
2. It filters out certain links. By default, this is any link that doesn't end in `.apk` but you can use "Custom APK Link Filter" to specify your own filter.
3. It sorts the remaining links. This sorting is alphanumeric sorting on the whole link, but you can choose to sort by only the last segment of the link. This last segment is usually the filename but may not be if you used your own filter in step 2.
4. It applies yet another optional user-defined filter on all remaining links. The difference between this filter and the one from step 2 is that this one is a more general filter that all Sources have - it is inherited from the parent `AppSource` class (the APK filter option described in [App Sources](#app-sources)). It's probably easier to use this in some situations rather than having a single more complicated regular expression in step 2 (see [this comment](https://github.com/ImranR98/Obtainium/issues/954#issuecomment-1745977857) for an example). It is also useful when used in combination with the intermediate link option.
5. Of the remaining links, it picks the first one (or the last one if you enabled the reverse option).
6. Now that we have the final APK link, we need a unique release ID to go with it so that when the ID changes, we know the app has an update available. For other Sources, the unique release ID is the app version, but for the HTML Source, it might not be possible to extract a version string. So by default, this is just a hash of the link.
    - However, links often have version strings embedded within them. Obtainium can't know how to extract these on its own (different websites would have different ways of doing it), so the user can choose to specify a regular expression that can be applied to the link in order to extract the version  - this is what the "Version Extraction" field is for.
    - But often it can be difficult to come up with a regular expression that accurately matches the version while excluding extra characters. For this, we have the "Match Group" option that lets the user specify which group in the regular expression we should use as a version.
    - The version extraction feature isn't really necessary - using link hashes is easier and more reliable. Some users might just want it since having the real version looks nicer/more accurate and it allows Obtainium, in most cases, to use [version detection](app_tracking.md/#version-detection).

As for the "Intermediate Link" filter, if this is used, the HTML Source works as follows (see [issue #820](https://github.com/ImranR98/Obtainium/issues/820) for a situation where this is useful):

1. It looks for links on an HTML page.
2. It filters out any links that don't match the intermediate link filter.
3. It grabs the first remaining link (no reverse option here), and then feeds that link as the input for the normal HTML Source process described previously.

## Notes for Various Other Sources

- HTML: Note that the HTML source includes default request headers that should be appropriate for most sites. In some cases (for example [SourceForge](https://sourceforge.net/), you may need to delete them (and possibly specify your own). 
- Codeberg: This source is almost identical to GitHub in its additional options.
- F-Droid: Any app from F-Droid is likely to be [signed](https://developer.android.com/studio/publish/app-signing) with a different key than releases of the same app from other sources. This means that trying to update from an F-Droid release of a given app to a release from another source (for example GitHub) is likely to fail.
- Any Source that does not have a specific host associated with it (like [third-party F-Droid repos](#f-droid-third-party-repo), Jenkins instances, and SourceHut instances) will not be automatically recognized by Obtainium. You must manually pick the right source from the "Override Source" dropdown.
- Some sources (like APKPure) may provide [XAPK files](https://apkpure.com/xapk.html) instead of APK files. Obtainium's XAPK support is incomplete and may not work reliably.