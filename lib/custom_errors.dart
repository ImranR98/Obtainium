import 'package:flutter/material.dart';
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

class RateLimitError {
  late int remainingMinutes;
  RateLimitError(this.remainingMinutes);

  @override
  String toString() =>
      'Too many requests (rate limited) - try again in $remainingMinutes minutes';
}

class InvalidURLError extends ObtainiumError {
  InvalidURLError(String sourceName) : super('Not a valid $sourceName App URL');
}

class NoReleasesError extends ObtainiumError {
  NoReleasesError() : super('Could not find a suitable release');
}

class NoAPKError extends ObtainiumError {
  NoAPKError() : super('Could not find a suitable release');
}

class NoVersionError extends ObtainiumError {
  NoVersionError() : super('Could not determine release version');
}

class UnsupportedURLError extends ObtainiumError {
  UnsupportedURLError() : super('URL does not match a known source');
}

class DowngradeError extends ObtainiumError {
  DowngradeError() : super('Cannot install an older version of an App');
}

class IDChangedError extends ObtainiumError {
  IDChangedError()
      : super('Downloaded package ID does not match existing App ID');
}

class NotImplementedError extends ObtainiumError {
  NotImplementedError() : super('This class has not implemented this function');
}

class MultiAppMultiError extends ObtainiumError {
  Map<String, List<String>> content = {};

  MultiAppMultiError() : super('Multiple Errors Placeholder', unexpected: true);

  add(String appId, String string) {
    var tempIds = content.remove(string);
    tempIds ??= [];
    tempIds.add(appId);
    content.putIfAbsent(string, () => tempIds!);
  }

  @override
  String toString() {
    String finalString = '';
    for (var e in content.keys) {
      finalString += '$e: ${content[e].toString()}\n\n';
    }
    return finalString;
  }
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
                ? 'Some Errors Occurred'
                : 'Unexpected Error'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(null);
                  },
                  child: const Text('Ok')),
            ],
          );
        });
  }
}

String list2FriendlyString(List<String> list) {
  return list.length == 2
      ? '${list[0]} and ${list[1]}'
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
