import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:ui' show Locale;

import 'package:easy_localization/easy_localization.dart';
import 'package:android_package_installer/android_package_installer.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

class ObtainiumError {
  final String code;
  final String _message;
  final StackTrace? stack;
  final Map<String, dynamic> data;
  final bool unexpected;

  /// The app/source URL this error relates to, if known. Attached as context so
  /// that logs and error messages can identify which app/URL an error came from
  /// even when the error itself was thrown deep inside a source with no app
  /// reference. Not part of the localized [message]; only surfaced via
  /// [toString].
  String? url;

  ObtainiumError(
    this._message, {
    this.code = 'UNKNOWN',
    this.unexpected = false,
    this.stack,
    this.data = const {},
    this.url,
  });

  ObtainiumError.withCode(
    this.code, {
    this._message = '',
    this.unexpected = false,
    this.stack,
    this.data = const {},
    this.url,
  });

  String get message =>
      code == 'UNKNOWN' ||
          code == 'UNEXPECTED' ||
          code == 'CHECK_UPDATES_FAILED' ||
          code == 'HTTP_ERROR'
      ? _message
      : localizeErrorCode(code, data);

  /// Attaches [contextUrl] as the offending URL if none is set yet, so logs and
  /// messages can identify the app/URL involved. Returns this for chaining.
  ObtainiumError withUrlContext(String? contextUrl) {
    if ((url == null || url!.isEmpty) &&
        contextUrl != null &&
        contextUrl.isNotEmpty) {
      url = contextUrl;
    }
    return this;
  }

  @override
  String toString() =>
      url != null && url!.isNotEmpty ? '$message ($url)' : message;
}

Never rethrowOrWrapError(
  Object error, {
  String? sourceName,
  StackTrace? stack,
}) {
  if (error is ObtainiumError) {
    if (error.unexpected) {
      final resolvedStack = error.stack ?? StackTrace.current;
      unawaited(
        LogsProvider().add(
          'Unexpected ObtainiumError: ${error.toString()}\n$resolvedStack',
          level: LogLevel.error,
        ),
      );
      throw ObtainiumError(
        error.message,
        code: 'UNEXPECTED',
        unexpected: true,
        stack: resolvedStack,
        data: error.data,
        url: error.url,
      );
    }
    throw error;
  }
  final capturedStack = stack ?? StackTrace.current;
  unawaited(
    LogsProvider().add(
      'Wrapping unexpected error: $error\n$capturedStack',
      level: LogLevel.error,
    ),
  );
  throw ObtainiumError(
    sourceName != null ? '$sourceName: $error' : error.toString(),
    code: 'UNEXPECTED',
    unexpected: true,
    stack: capturedStack,
  );
}

class RateLimitError extends ObtainiumError {
  final int remainingMinutes;
  RateLimitError(this.remainingMinutes)
    : super.withCode(
        'RATE_LIMIT',
        data: {'remainingMinutes': remainingMinutes},
      );
}

class InvalidURLError extends ObtainiumError {
  InvalidURLError(String sourceName)
    : super.withCode('INVALID_URL', data: {'sourceName': sourceName});
}

class CredsNeededError extends ObtainiumError {
  CredsNeededError(String sourceName)
    : super.withCode('CREDS_NEEDED', data: {'sourceName': sourceName});
}

class NoReleasesError extends ObtainiumError {
  NoReleasesError({String? note})
    : super.withCode('NO_RELEASES', data: {'note': note ?? ''});
}

class NoAPKError extends ObtainiumError {
  NoAPKError() : super.withCode('NO_APK');
}

class NoVersionError extends ObtainiumError {
  NoVersionError() : super.withCode('NO_VERSION');
}

class UnsupportedURLError extends ObtainiumError {
  UnsupportedURLError() : super.withCode('UNSUPPORTED_URL');
}

class DowngradeError extends ObtainiumError {
  DowngradeError(int currentVersionCode, int newVersionCode)
    : super.withCode(
        'DOWNGRADE',
        data: {
          'currentVersionCode': currentVersionCode,
          'newVersionCode': newVersionCode,
        },
      );
}

class InstallError extends ObtainiumError {
  InstallError(int code)
    : super.withCode(
        'INSTALL_FAILED',
        data: {
          'errorCode': code,
          'message': PackageInstallerStatus.byCode(code).name,
        },
      );
}

class IDChangedError extends ObtainiumError {
  IDChangedError(String newId)
    : super.withCode('ID_CHANGED', data: {'newId': newId});
}

class RepositoryRenamedError extends ObtainiumError {
  final String oldUrl;
  final String newUrl;
  RepositoryRenamedError(this.oldUrl, this.newUrl)
    : super.withCode(
        'REPO_RENAMED',
        data: {'oldUrl': oldUrl, 'newUrl': newUrl},
      );
}

class CheckUpdatesException extends ObtainiumError {
  final List<App> updates;
  final MultiAppMultiError errors;
  CheckUpdatesException(this.updates, this.errors)
    : super.withCode('CHECK_UPDATES_FAILED', unexpected: true);
  @override
  String toString() => errors.toString();
}

class NotImplementedError extends ObtainiumError {
  NotImplementedError() : super.withCode('NOT_IMPLEMENTED');
}

class MultiAppMultiError extends ObtainiumError {
  Map<String, dynamic> rawErrors = {};
  Map<String, List<String>> idsByErrorString = {};
  Map<String, String> appIdNames = {};

  MultiAppMultiError() : super.withCode('MULTI_ERROR', unexpected: true);

  void add(String appId, dynamic error, {String? appName}) {
    if (error is SocketException) {
      // Use the concise message rather than the verbose OS-level toString.
      error = error.message;
    }
    rawErrors[appId] = error;
    final string = error.toString();
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

String localizeErrorCode(String code, Map<String, dynamic>? data) {
  return switch (code) {
    'NO_RELEASES' =>
      data?['note'] != null && (data!['note'] as String).isNotEmpty
          ? '${tr('noReleaseFound')}\n\n${data['note']}'
          : tr('noReleaseFound'),
    'RATE_LIMIT' => plural(
      'tooManyRequestsTryAgainInMinutes',
      data?['remainingMinutes'] ?? 0,
    ),
    'INVALID_URL' => tr(
      'invalidURLForSource',
      args: [data?['sourceName'] ?? ''],
    ),
    'CREDS_NEEDED' => tr(
      'requiresCredentialsInSettings',
      args: [data?['sourceName'] ?? ''],
    ),
    'NO_APK' => tr('noAPKFound'),
    'NO_VERSION' => tr('noVersionFound'),
    'UNSUPPORTED_URL' => tr('urlMatchesNoSource'),
    'DOWNGRADE' =>
      '${tr('cantInstallOlderVersion')} (versionCode ${data?['currentVersionCode'] ?? '?'} → ${data?['newVersionCode'] ?? '?'})',
    'INSTALL_FAILED' => data?['message']?.toString() ?? tr('installFailed'),
    'ID_CHANGED' => '${tr('appIdMismatch')} - ${data?['newId'] ?? ''}',
    'REPO_RENAMED' => tr('repoRenamed'),
    'NOT_IMPLEMENTED' => tr('functionNotImplemented'),
    _ => data?['message']?.toString() ?? tr('unexpectedError'),
  };
}

Locale? _appCurrentLocale;

void setAppLocale(Locale? locale) => _appCurrentLocale = locale;

String? get currentLanguageCode => _appCurrentLocale?.languageCode;

bool isEnglish() {
  if (_appCurrentLocale != null) return _appCurrentLocale!.languageCode == 'en';
  return false;
}

String lowerCaseIfEnglish(String str) => isEnglish() ? str.toLowerCase() : str;

String list2FriendlyString(List<String> list) {
  final isUsingEnglish = isEnglish();
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
