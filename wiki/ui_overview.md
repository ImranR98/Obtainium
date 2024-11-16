---
title: UI Overview
description: Overview of the Obtainium UI
---

# UI Overview

The tab bar at the bottom of the screen is the main way to navigate around Obtainium.

## Apps Page

This is the main screen; it contains a list of apps being tracked by Obtainium, and provides the basic info for each app.

On this page, you can use the buttons at the bottom of the screen to perform various operations (like delete, update, tag, etc.) on multiple apps at once. You can do this after selecting one or more apps, either using a long-press to enter multi-select mode or using the "select all" button.

You can also filter for specific apps by pressing the filter button. This lets you view only the apps that fulfill specific criteria (like installed/not-installed, latest/outdated, source site, etc.).

## Add App Page

This page lets you add an app by its source URL.

As you enter the source URL, Obtainium will automatically detect what [source logic](app_tracking.md/#basics) it should use, and will present the relevant options. If a URL does not correspond to any supported source, the "[HTML](sources.md/#html)" source will be selected as a default. This source is a general fallback that may work in some cases. If you think Obtainium has made the wrong choice, you can manually specify the source type to use.

For most sources, you don't need to be exact with the URL you enter; for example, any GitHub URL that contains the base repo URL would be accepted by the GitHub source (for example, `https://github.com/ImranR98/Obtainium/releases/latest` would automatically be trimmed down to `https://github.com/ImranR98/Obtainium`). However, your URL must be more precise in two situations:
1. When using the HTML source
   - For example, the Tor Android APK is at `https://www.torproject.org/download/` so entering only `https://www.torproject.org/` would not work.
2. When manually picking a source (overriding Obtainium's HTML fallback choice)

This page also lets you search for apps across sources that support this feature (the [Import/Export](#importexport-page) page also provides a separate search tool). Note that just because an app shows up in the search results does not mean it will be added successfully - it still needs to fulfill all other criteria.

Finally, this page lists all supported sources, along with additional info such as whether a source is searchable.

## Import/Export Page

This page lets you export your Obtainium data so that it can be imported later. You can also enable automatic exports that happen whenever any data changes.

This page also provides various other ways of importing large numbers of apps, including through search.

The search tool on this page also lets you search sources that require you to specify the source host/domain, such as [third-party F-Droid repos](sources.md/#f-droid-third-party-repo).

## Settings Page

This page provides various UI and behaviour settings, including the option to enable more functionality for specific sources by adding required credentials.