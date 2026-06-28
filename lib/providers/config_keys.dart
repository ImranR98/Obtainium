// Typed constants for [App.additionalSettings] keys and related configuration.
// Using these instead of raw string literals gives compile-time typo protection.

class AppConfigKey {
  AppConfigKey._();

  // Core
  static const String trackOnly = 'trackOnly';
  static const String versionDetection = 'versionDetection';
  static const String versionExtractionRegEx = 'versionExtractionRegEx';
  static const String matchGroupToUse = 'matchGroupToUse';
  static const String releaseDateAsVersion = 'releaseDateAsVersion';
  static const String useVersionCodeAsOSVersion = 'useVersionCodeAsOSVersion';

  // APK filtering
  static const String apkFilterRegEx = 'apkFilterRegEx';
  static const String invertAPKFilter = 'invertAPKFilter';
  static const String autoApkFilterByArch = 'autoApkFilterByArch';

  // Display overrides
  static const String appName = 'appName';
  static const String appAuthor = 'appAuthor';
  static const String about = 'about';

  // Download / install
  static const String allowInsecure = 'allowInsecure';
  static const String refreshBeforeDownload = 'refreshBeforeDownload';
  static const String shizukuPretendToBeGooglePlay = 'shizukuPretendToBeGooglePlay';

  // Background updates
  static const String exemptFromBackgroundUpdates = 'exemptFromBackgroundUpdates';
  static const String skipUpdateNotifications = 'skipUpdateNotifications';

  // App ID
  static const String appId = 'appId';

  // Pseudo versioning
  static const String defaultPseudoVersioningMethod = 'defaultPseudoVersioningMethod';
  static const String supportFixedAPKURL = 'supportFixedAPKURL';

  // GitHub-specific
  static const String includePrereleases = 'includePrereleases';
  static const String fallbackToOlderReleases = 'fallbackToOlderReleases';
  static const String filterReleaseTitlesByRegEx = 'filterReleaseTitlesByRegEx';
  static const String sortMethodChoice = 'sortMethodChoice';
  static const String verifyLatestTag = 'verifyLatestTag';
  static const String releaseTitleAsVersion = 'releaseTitleAsVersion';
  static const String checkRepoRename = 'checkRepoRename';
  static const String useLatestAssetDateAsReleaseDate = 'useLatestAssetDateAsReleaseDate';

  // HTML-specific
  static const String customLinkFilterRegex = 'customLinkFilterRegex';
  static const String sortByLastLinkSegment = 'sortByLastLinkSegment';
  static const String intermediateLink = 'intermediateLink';

  // ZIP / tarball
  static const String includeZips = 'includeZips';
  static const String includeTarballs = 'includeTarballs';
  static const String zippedApkFilterRegEx = 'zippedApkFilterRegEx';
  static const String tarballedApkFilterRegEx = 'tarballedApkFilterRegEx';
}
