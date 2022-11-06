import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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

showError(dynamic e, BuildContext context) {
  if (e is String || e is ObtainiumError) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  } else {
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            scrollable: true,
            title: const Text('Unexpected Error'),
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
