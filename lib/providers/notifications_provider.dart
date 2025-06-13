// Exposes functions that can be used to send notifications to the user
// Contains a set of pre-defined ObtainiumNotification objects that should be used throughout the app

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

class ObtainiumNotification {
  late int id;
  late String title;
  late String message;
  late String channelCode;
  late String channelName;
  late String channelDescription;
  Importance importance;
  int? progPercent;
  bool onlyAlertOnce;
  String? payload;

  ObtainiumNotification(
    this.id,
    this.title,
    this.message,
    this.channelCode,
    this.channelName,
    this.channelDescription,
    this.importance, {
    this.onlyAlertOnce = false,
    this.progPercent,
    this.payload,
  });
}

class UpdateNotification extends ObtainiumNotification {
  UpdateNotification(List<App> updates, {int? id})
    : super(
        id ?? 2,
        tr('updatesAvailable'),
        '',
        'UPDATES_AVAILABLE',
        tr('updatesAvailableNotifChannel'),
        tr('updatesAvailableNotifDescription'),
        Importance.max,
      ) {
    message = updates.isEmpty
        ? tr('noNewUpdates')
        : updates.length == 1
        ? tr('xHasAnUpdate', args: [updates[0].finalName])
        : plural(
            'xAndNMoreUpdatesAvailable',
            updates.length - 1,
            args: [updates[0].finalName, (updates.length - 1).toString()],
          );
  }
}

class SilentUpdateNotification extends ObtainiumNotification {
  SilentUpdateNotification(List<App> updates, bool succeeded, {int? id})
    : super(
        id ?? 3,
        succeeded ? tr('appsUpdated') : tr('appsNotUpdated'),
        '',
        'APPS_UPDATED',
        tr('appsUpdatedNotifChannel'),
        tr('appsUpdatedNotifDescription'),
        Importance.defaultImportance,
      ) {
    message = updates.length == 1
        ? tr(
            succeeded ? 'xWasUpdatedToY' : 'xWasNotUpdatedToY',
            args: [updates[0].finalName, updates[0].latestVersion],
          )
        : plural(
            succeeded ? 'xAndNMoreUpdatesInstalled' : "xAndNMoreUpdatesFailed",
            updates.length - 1,
            args: [updates[0].finalName, (updates.length - 1).toString()],
          );
  }
}

class SilentUpdateAttemptNotification extends ObtainiumNotification {
  SilentUpdateAttemptNotification(List<App> updates, {int? id})
    : super(
        id ?? 3,
        tr('appsPossiblyUpdated'),
        '',
        'APPS_POSSIBLY_UPDATED',
        tr('appsPossiblyUpdatedNotifChannel'),
        tr('appsPossiblyUpdatedNotifDescription'),
        Importance.defaultImportance,
      ) {
    message = updates.length == 1
        ? tr(
            'xWasPossiblyUpdatedToY',
            args: [updates[0].finalName, updates[0].latestVersion],
          )
        : plural(
            'xAndNMoreUpdatesPossiblyInstalled',
            updates.length - 1,
            args: [updates[0].finalName, (updates.length - 1).toString()],
          );
  }
}

class ErrorCheckingUpdatesNotification extends ObtainiumNotification {
  ErrorCheckingUpdatesNotification(String error, {int? id})
    : super(
        id ?? 5,
        tr('errorCheckingUpdates'),
        error,
        'BG_UPDATE_CHECK_ERROR',
        tr('errorCheckingUpdatesNotifChannel'),
        tr('errorCheckingUpdatesNotifDescription'),
        Importance.high,
        payload: "${tr('errorCheckingUpdates')}\n$error",
      );
}

class AppsRemovedNotification extends ObtainiumNotification {
  AppsRemovedNotification(List<List<String>> namedReasons)
    : super(
        6,
        tr('appsRemoved'),
        '',
        'APPS_REMOVED',
        tr('appsRemovedNotifChannel'),
        tr('appsRemovedNotifDescription'),
        Importance.max,
      ) {
    message = '';
    for (var r in namedReasons) {
      message += '${tr('xWasRemovedDueToErrorY', args: [r[0], r[1]])} \n';
    }
    message = message.trim();
  }
}

class DownloadNotification extends ObtainiumNotification {
  DownloadNotification(String appName, int progPercent)
    : super(
        appName.hashCode,
        tr('downloadingX', args: [appName]),
        '',
        'APP_DOWNLOADING',
        tr('downloadingXNotifChannel', args: [tr('app')]),
        tr('downloadNotifDescription'),
        Importance.low,
        onlyAlertOnce: true,
        progPercent: progPercent,
      );
}

class DownloadedNotification extends ObtainiumNotification {
  DownloadedNotification(String fileName, String downloadUrl)
    : super(
        downloadUrl.hashCode,
        tr('downloadedX', args: [fileName]),
        '',
        'FILE_DOWNLOADED',
        tr('downloadedXNotifChannel', args: [tr('app')]),
        tr('downloadedX', args: [tr('app')]),
        Importance.defaultImportance,
      );
}

final completeInstallationNotification = ObtainiumNotification(
  1,
  tr('completeAppInstallation'),
  tr('obtainiumMustBeOpenToInstallApps'),
  'COMPLETE_INSTALL',
  tr('completeAppInstallationNotifChannel'),
  tr('completeAppInstallationNotifDescription'),
  Importance.max,
);

class CheckingUpdatesNotification extends ObtainiumNotification {
  CheckingUpdatesNotification(String appName)
    : super(
        4,
        tr('checkingForUpdates'),
        appName,
        'BG_UPDATE_CHECK',
        tr('checkingForUpdatesNotifChannel'),
        tr('checkingForUpdatesNotifDescription'),
        Importance.min,
      );
}

class NotificationsProvider {
  FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  bool isInitialized = false;

  Map<Importance, Priority> importanceToPriority = {
    Importance.defaultImportance: Priority.defaultPriority,
    Importance.high: Priority.high,
    Importance.low: Priority.low,
    Importance.max: Priority.max,
    Importance.min: Priority.min,
    Importance.none: Priority.min,
    Importance.unspecified: Priority.defaultPriority,
  };

  Future<void> initialize() async {
    isInitialized =
        await notifications.initialize(
          const InitializationSettings(
            android: AndroidInitializationSettings('ic_notification'),
          ),
          onDidReceiveNotificationResponse: (NotificationResponse response) {
            _showNotificationPayload(response.payload);
          },
        ) ??
        false;
  }

  Future<void> checkLaunchByNotif() async {
    final NotificationAppLaunchDetails? launchDetails = await notifications
        .getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _showNotificationPayload(
        launchDetails!.notificationResponse?.payload,
        doublePop: true,
      );
    }
  }

  void _showNotificationPayload(String? payload, {bool doublePop = false}) {
    if (payload?.isNotEmpty == true) {
      var title = (payload ?? '\n\n').split('\n').first;
      var content = (payload ?? '\n\n').split('\n').sublist(1).join('\n');
      globalNavigatorKey.currentState?.push(
        PageRouteBuilder(
          pageBuilder: (context, _, __) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(null);
                  if (doublePop) {
                    Navigator.of(context).pop(null);
                  }
                },
                child: Text(tr('ok')),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> cancel(int id) async {
    if (!isInitialized) {
      await initialize();
    }
    await notifications.cancel(id);
  }

  Future<void> notifyRaw(
    int id,
    String title,
    String message,
    String channelCode,
    String channelName,
    String channelDescription,
    Importance importance, {
    bool cancelExisting = false,
    int? progPercent,
    bool onlyAlertOnce = false,
    String? payload,
  }) async {
    if (cancelExisting) {
      await cancel(id);
    }
    if (!isInitialized) {
      await initialize();
    }
    await notifications.show(
      id,
      title,
      message,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelCode,
          channelName,
          channelDescription: channelDescription,
          importance: importance,
          priority: importanceToPriority[importance]!,
          groupKey: '$obtainiumId.$channelCode',
          progress: progPercent ?? 0,
          maxProgress: 100,
          showProgress: progPercent != null,
          onlyAlertOnce: onlyAlertOnce,
          indeterminate: progPercent != null && progPercent < 0,
        ),
      ),
      payload: payload,
    );
  }

  Future<void> notify(
    ObtainiumNotification notif, {
    bool cancelExisting = false,
  }) => notifyRaw(
    notif.id,
    notif.title,
    notif.message,
    notif.channelCode,
    notif.channelName,
    notif.channelDescription,
    notif.importance,
    cancelExisting: cancelExisting,
    onlyAlertOnce: notif.onlyAlertOnce,
    progPercent: notif.progPercent,
    payload: notif.payload,
  );
}
