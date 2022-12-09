// Exposes functions that can be used to send notifications to the user
// Contains a set of pre-defined ObtainiumNotification objects that should be used throughout the app

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

  ObtainiumNotification(this.id, this.title, this.message, this.channelCode,
      this.channelName, this.channelDescription, this.importance,
      {this.onlyAlertOnce = false, this.progPercent});
}

class UpdateNotification extends ObtainiumNotification {
  UpdateNotification(List<App> updates)
      : super(
            2,
            tr('updatesAvailable'),
            '',
            'UPDATES_AVAILABLE',
            tr('updatesAvailable'),
            tr('updatesAvailableNotifDescription'),
            Importance.max) {
    message = updates.isEmpty
        ? tr('noNewUpdates')
        : updates.length == 1
            ? tr('xHasAnUpdate', args: [updates[0].name])
            : plural('xAndNMoreUpdatesAvailable', updates.length - 1,
                args: [updates[0].name]);
  }
}

class SilentUpdateNotification extends ObtainiumNotification {
  SilentUpdateNotification(List<App> updates)
      : super(3, tr('appsUpdated'), '', 'APPS_UPDATED', tr('appsUpdated'),
            tr('appsUpdatedNotifDescription'), Importance.defaultImportance) {
    message = updates.length == 1
        ? tr('xWasUpdatedToY',
            args: [updates[0].name, updates[0].latestVersion])
        : plural('xAndNMoreUpdatesInstalled', updates.length - 1,
            args: [updates[0].name]);
  }
}

class ErrorCheckingUpdatesNotification extends ObtainiumNotification {
  ErrorCheckingUpdatesNotification(String error)
      : super(
            5,
            tr('errorCheckingUpdates'),
            error,
            'BG_UPDATE_CHECK_ERROR',
            tr('errorCheckingUpdates'),
            tr('errorCheckingUpdatesNotifDescription'),
            Importance.high);
}

class AppsRemovedNotification extends ObtainiumNotification {
  AppsRemovedNotification(List<List<String>> namedReasons)
      : super(6, tr('appsRemoved'), '', 'APPS_REMOVED', tr('appsRemoved'),
            tr('appsRemovedNotifDescription'), Importance.max) {
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
            'Downloading $appName',
            '',
            'APP_DOWNLOADING',
            'Downloading App',
            'Notifies the user of the progress in downloading an App',
            Importance.low,
            onlyAlertOnce: true,
            progPercent: progPercent);
}

final completeInstallationNotification = ObtainiumNotification(
    1,
    tr('completeAppInstallation'),
    tr('obtainiumMustBeOpenToInstallApps'),
    'COMPLETE_INSTALL',
    tr('completeAppInstallation'),
    tr('completeAppInstallationNotifDescription'),
    Importance.max);

final checkingUpdatesNotification = ObtainiumNotification(
    4,
    tr('checkingForUpdates'),
    '',
    'BG_UPDATE_CHECK',
    tr('checkingForUpdates'),
    tr('checkingForUpdatesNotifDescription'),
    Importance.min);

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
    Importance.unspecified: Priority.defaultPriority
  };

  Future<void> initialize() async {
    isInitialized = await notifications.initialize(const InitializationSettings(
            android: AndroidInitializationSettings('ic_notification'))) ??
        false;
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
      Importance importance,
      {bool cancelExisting = false,
      int? progPercent,
      bool onlyAlertOnce = false}) async {
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
            android: AndroidNotificationDetails(channelCode, channelName,
                channelDescription: channelDescription,
                importance: importance,
                priority: importanceToPriority[importance]!,
                groupKey: 'dev.imranr.obtainium.$channelCode',
                progress: progPercent ?? 0,
                maxProgress: 100,
                showProgress: progPercent != null,
                onlyAlertOnce: onlyAlertOnce)));
  }

  Future<void> notify(ObtainiumNotification notif,
          {bool cancelExisting = false}) =>
      notifyRaw(notif.id, notif.title, notif.message, notif.channelCode,
          notif.channelName, notif.channelDescription, notif.importance,
          cancelExisting: cancelExisting,
          onlyAlertOnce: notif.onlyAlertOnce,
          progPercent: notif.progPercent);
}
