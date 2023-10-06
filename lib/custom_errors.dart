import 'package:android_package_installer/android_package_installer.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:provider/provider.dart';

class ObtainiumError {
  late String message;
  bool unexpected;
  ObtainiumError(this.message, {this.unexpected = false});
  @override
  String toString() {
    return message;
  }
}

class RateLimitError extends ObtainiumError {
  late int remainingMinutes;
  RateLimitError(this.remainingMinutes)
      : super(plural('tooManyRequestsTryAgainInMinutes', remainingMinutes));
}

class InvalidURLError extends ObtainiumError {
  InvalidURLError(String sourceName)
      : super(tr('invalidURLForSource', args: [sourceName]));
}

class CredsNeededError extends ObtainiumError {
  CredsNeededError(String sourceName)
      : super(tr('requiresCredentialsInSettings', args: [sourceName]));
}

class NoReleasesError extends ObtainiumError {
  NoReleasesError() : super(tr('noReleaseFound'));
}

class NoAPKError extends ObtainiumError {
  NoAPKError() : super(tr('noAPKFound'));
}

class NoVersionError extends ObtainiumError {
  NoVersionError() : super(tr('noVersionFound'));
}

class UnsupportedURLError extends ObtainiumError {
  UnsupportedURLError() : super(tr('urlMatchesNoSource'));
}

class DowngradeError extends ObtainiumError {
  DowngradeError() : super(tr('cantInstallOlderVersion'));
}

class InstallError extends ObtainiumError {
  InstallError(int code)
      : super(PackageInstallerStatus.byCode(code).name.substring(7));
}

class IDChangedError extends ObtainiumError {
  IDChangedError(String newId) : super('${tr('appIdMismatch')} - $newId');
}

class NotImplementedError extends ObtainiumError {
  NotImplementedError() : super(tr('functionNotImplemented'));
}

class MultiAppMultiError extends ObtainiumError {
  Map<String, dynamic> rawErrors = {};
  Map<String, List<String>> idsByErrorString = {};
  Map<String, String> appIdNames = {};

  MultiAppMultiError() : super(tr('placeholder'), unexpected: true);

  add(String appId, dynamic error, {String? appName}) {
    rawErrors[appId] = error;
    var string = error.toString();
    var tempIds = idsByErrorString.remove(string);
    tempIds ??= [];
    tempIds.add(appId);
    idsByErrorString.putIfAbsent(string, () => tempIds!);
    if (appName != null) {
      appIdNames[appId] = appName;
    }
  }

  String errorString(String appId) =>
      '${appIdNames.containsKey(appId) ? '${appIdNames[appId]} ($appId)' : appId}: ${rawErrors[appId].toString()}';

  @override
  String toString() =>
      idsByErrorString.keys.map((e) => errorString(e)).join('\n\n');
}

showError(dynamic e, BuildContext context) {
  Provider.of<LogsProvider>(context, listen: false)
      .add(e.toString(), level: LogLevels.error);
  if (e is String || (e is ObtainiumError && !e.unexpected)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  } else {
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            scrollable: true,
            title: Text(e is MultiAppMultiError
                ? tr('someErrors')
                : tr('unexpectedError')),
            content: GestureDetector(
                onLongPress: () {
                  Clipboard.setData(ClipboardData(text: e.toString()));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(tr('copiedToClipboard')),
                  ));
                },
                child: Text(e.toString())),
            actions: [
              TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(null);
                  },
                  child: Text(tr('ok'))),
            ],
          );
        });
  }
}

String list2FriendlyString(List<String> list) {
  return list.length == 2
      ? '${list[0]} ${tr('and')} ${list[1]}'
      : list
          .asMap()
          .entries
          .map((e) =>
              e.value +
              (e.key == list.length - 1
                  ? ''
                  : e.key == list.length - 2
                      ? ', and '
                      : ', '))
          .join('');
}
