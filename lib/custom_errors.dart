// Obtainium-specific error classes used throughout the app.

import 'dart:io';

import 'package:android_package_installer/android_package_installer.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:obtainium/providers/source_provider.dart';

/// Base class for all Obtainium-specific errors, wrapping a human-readable message.
class ObtainiumError {
  final String message;
  bool unexpected;
  ObtainiumError(this.message, {this.unexpected = false});
  @override
  String toString() {
    return message;
  }
}

/// Thrown when an HTTP response indicates a rate limit has been exceeded.
class RateLimitError extends ObtainiumError {
  final int remainingMinutes;
  RateLimitError(this.remainingMinutes)
    : super(plural('tooManyRequestsTryAgainInMinutes', remainingMinutes));
}

/// Thrown when a URL does not match the expected format for the given source.
class InvalidURLError extends ObtainiumError {
  InvalidURLError(String sourceName)
    : super(tr('invalidURLForSource', args: [sourceName]));
}

/// Thrown when a source requires credentials that have not been configured.
class CredsNeededError extends ObtainiumError {
  CredsNeededError(String sourceName)
    : super(tr('requiresCredentialsInSettings', args: [sourceName]));
}

/// Thrown when a source returns no releases or assets for the requested app.
class NoReleasesError extends ObtainiumError {
  NoReleasesError({String? note})
    : super(
        '${tr('noReleaseFound')}${note?.isNotEmpty == true ? '\n\n$note' : ''}',
      );
}

/// Thrown when no installable APK files were found for the app.
class NoAPKError extends ObtainiumError {
  NoAPKError() : super(tr('noAPKFound'));
}

/// Thrown when version information could not be extracted from the source data.
class NoVersionError extends ObtainiumError {
  NoVersionError() : super(tr('noVersionFound'));
}

/// Thrown when a URL does not match any supported app source.
class UnsupportedURLError extends ObtainiumError {
  UnsupportedURLError() : super(tr('urlMatchesNoSource'));
}

/// Thrown when attempting to install an older version of an app over a newer one.
class DowngradeError extends ObtainiumError {
  DowngradeError(int currentVersionCode, int newVersionCode)
    : super(
        '${tr('cantInstallOlderVersion')} (versionCode $currentVersionCode ➔ $newVersionCode)',
      );
}

/// Thrown when the Android package installer returns a failure status code.
class InstallError extends ObtainiumError {
  InstallError(int code)
    : super(PackageInstallerStatus.byCode(code).name);
}

/// Thrown when a downloaded APK's package ID differs from the expected app ID.
class IDChangedError extends ObtainiumError {
  IDChangedError(String newId) : super('${tr('appIdMismatch')} - $newId');
}

/// Thrown when a source repository has been renamed or moved, carrying the new URL.
class RepositoryRenamedError extends ObtainiumError {
  final String oldUrl;
  final String newUrl;
  RepositoryRenamedError(this.oldUrl, this.newUrl) : super(tr('repoRenamed'));
}

/// Carries the partial [updates] and [errors] results from a batch update check
/// that encountered non-retryable failures.
class CheckUpdatesException extends ObtainiumError {
  final List<App> updates;
  final MultiAppMultiError errors;
  CheckUpdatesException(this.updates, this.errors) : super('', unexpected: true);
  @override
  String toString() => errors.toString();
}

/// Thrown when a source method that hasn't been implemented is called.
class NotImplementedError extends ObtainiumError {
  NotImplementedError() : super(tr('functionNotImplemented'));
}

/// Aggregates errors from multiple apps into a single error, grouped by error string.
class MultiAppMultiError extends ObtainiumError {
  Map<String, dynamic> rawErrors = {};
  Map<String, List<String>> idsByErrorString = {};
  Map<String, String> appIdNames = {};

  MultiAppMultiError() : super(tr('placeholder'), unexpected: true);

  void add(String appId, dynamic error, {String? appName}) {
    if (error is SocketException) {
      error = error.message;
    }
    rawErrors[appId] = error;
    var string = error.toString();
    var tempIds = idsByErrorString.remove(string);
    if (tempIds == null) {
      tempIds = [];
      idsByErrorString[string] = tempIds;
    }
    tempIds.add(appId);
    if (appName != null) {
      appIdNames[appId] = appName;
    }
  }

  String errorString(String appId, {bool includeIdsWithNames = false}) =>
      '${appIdNames.containsKey(appId) ? '${appIdNames[appId]}${includeIdsWithNames ? ' ($appId)' : ''}' : appId}: ${rawErrors[appId].toString()}';

  String errorsAppsString(
    String errString,
    List<String> appIds, {
    bool includeIdsWithNames = false,
  }) =>
      '$errString [${list2FriendlyString(appIds.map((id) => appIdNames.containsKey(id) == true ? '${appIdNames[id]}${includeIdsWithNames ? ' ($id)' : ''}' : id).toList())}]';

  @override
  String toString() => idsByErrorString.entries
      .map((e) => errorsAppsString(e.key, e.value))
      .join('\n\n');
}

String list2FriendlyString(List<String> list) {
  var isUsingEnglish = isEnglish();
  return list.length == 2
      ? '${list[0]} ${tr('and')} ${list[1]}'
      : list
            .asMap()
            .entries
            .map(
              (e) =>
                  e.value +
                  (e.key == list.length - 1
                      ? ''
                      : e.key == list.length - 2
                      ? '${isUsingEnglish ? ',' : ''} ${tr('and')} '
                      : ', '),
            )
            .join('');
}
