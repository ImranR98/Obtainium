import 'package:flutter/material.dart';
import 'package:obtainium/providers/apps_provider.dart';

class ObtainiumError {
  late String message;
  ObtainiumError(this.message);
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

class MultiAppMultiError extends ObtainiumError {
  Map<String, List<String>> content = {};

  MultiAppMultiError() : super('Multiple Errors Placeholder');

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
  if (e is String || (e is ObtainiumError && e is! MultiAppMultiError)) {
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
