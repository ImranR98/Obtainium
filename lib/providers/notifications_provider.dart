// Exposes functions that can be used to send notifications to the user.
//
// Contains a set of pre-defined ObtainiumNotification objects that should be used throughout the app.

import 'dart:isolate';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:obtainium/main.dart';
import 'package:obtainium/providers/apps_provider.dart' show formatDownloadSize;
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

/// Prefix for the download-notification Cancel action id; the app ID is appended
/// so the tap handler knows which download to stop.
const String cancelDownloadActionPrefix = 'cancel_download::';

const int updateNotificationId = 2;
const int silentUpdateNotificationId = 3;
const int errorCheckingUpdatesNotificationId = 5;
const int trackOnlyUpdateNotificationId = 7;
const int silentUpdateAttemptNotificationId = 8;
const int downloadNotificationBaseId = 100;

/// Size of the ID space for per-download notifications. Kept just under the
/// 32-bit signed max (minus [downloadNotificationBaseId]) so download IDs stay
/// positive and clear of the small fixed IDs above, while making collisions
/// between concurrently downloading apps as unlikely as a raw hashCode.
const int downloadNotificationIdRange = 2000000000;

/// Name under which the main isolate registers a port to receive download-cancel
/// requests forwarded from the notification-action background isolate.
const String _downloadCancelPortName = 'obtainium_download_cancel';

/// The app ID targeted by a download-cancel notification action, or null if
/// [actionId] isn't a download-cancel action.
String? _cancelActionAppId(String? actionId) {
  if (actionId == null || !actionId.startsWith(cancelDownloadActionPrefix)) {
    return null;
  }
  final appId = actionId.substring(cancelDownloadActionPrefix.length);
  return appId.isEmpty ? null : appId;
}

/// Runs in a separate isolate when a notification action button is tapped (FLN
/// routes action taps here, not to the foreground handler). It can't touch app
/// state, so it forwards the cancel request to the main isolate via a named port.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final appId = _cancelActionAppId(response.actionId);
  if (appId != null) {
    IsolateNameServer.lookupPortByName(_downloadCancelPortName)?.send(appId);
  }
}

String _buildUpdateMessage(
  List<App> updates, {
  String? emptyKey,
  required String singleKey,
  required String pluralKey,
  bool includeVersion = false,
}) {
  if (updates.isEmpty) return emptyKey != null ? tr(emptyKey) : '';
  final name = updates[0].finalName;
  final version = updates[0].latestVersion;
  if (updates.length == 1) {
    final args = includeVersion ? [name, version] : [name];
    return tr(singleKey, args: args);
  }
  final count = updates.length - 1;
  return plural(pluralKey, count, args: [name, count.toString()]);
}

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
  List<AndroidNotificationAction>? androidActions;

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
    this.androidActions,
  });
}

class UpdateNotification extends ObtainiumNotification {
  UpdateNotification(List<App> updates, {int? id})
    : super(
        id ?? updateNotificationId,
        tr('updatesAvailable'),
        _buildUpdateMessage(
          updates,
          emptyKey: 'noNewUpdates',
          singleKey: 'xHasAnUpdate',
          pluralKey: 'xAndNMoreUpdatesAvailable',
        ),
        'UPDATES_AVAILABLE',
        tr('updatesAvailableNotifChannel'),
        tr('updatesAvailableNotifDescription'),
        Importance.max,
      );
}

class TrackOnlyUpdateNotification extends ObtainiumNotification {
  TrackOnlyUpdateNotification(List<App> updates, {int? id})
    : super(
        id ?? trackOnlyUpdateNotificationId,
        tr('trackOnlyUpdatesAvailable'),
        _buildUpdateMessage(
          updates,
          emptyKey: 'noNewUpdates',
          singleKey: 'xHasAnUpdate',
          pluralKey: 'xAndNMoreUpdatesAvailable',
        ),
        'UPDATES_AVAILABLE',
        tr('updatesAvailableNotifChannel'),
        tr('updatesAvailableNotifDescription'),
        Importance.max,
      );
}

class SilentUpdateNotification extends ObtainiumNotification {
  SilentUpdateNotification(List<App> updates, bool succeeded, {int? id})
    : super(
        id ?? 3,
        succeeded ? tr('appsUpdated') : tr('appsNotUpdated'),
        _buildUpdateMessage(
          updates,
          singleKey: succeeded ? 'xWasUpdatedToY' : 'xWasNotUpdatedToY',
          pluralKey: succeeded
              ? 'xAndNMoreUpdatesInstalled'
              : 'xAndNMoreUpdatesFailed',
          includeVersion: true,
        ),
        'APPS_UPDATED',
        tr('appsUpdatedNotifChannel'),
        tr('appsUpdatedNotifDescription'),
        Importance.defaultImportance,
      );
}

class SilentUpdateAttemptNotification extends ObtainiumNotification {
  SilentUpdateAttemptNotification(List<App> updates, {int? id})
    : super(
        id ?? 8,
        tr('appsPossiblyUpdated'),
        _buildUpdateMessage(
          updates,
          singleKey: 'xWasPossiblyUpdatedToY',
          pluralKey: 'xAndNMoreUpdatesPossiblyInstalled',
          includeVersion: true,
        ),
        'APPS_POSSIBLY_UPDATED',
        tr('appsPossiblyUpdatedNotifChannel'),
        tr('appsPossiblyUpdatedNotifDescription'),
        Importance.defaultImportance,
      );
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
    final buffer = StringBuffer();
    for (var r in namedReasons) {
      buffer.writeln(tr('xWasRemovedDueToErrorY', args: [r[0], r[1]]));
    }
    message = buffer.toString().trim();
  }
}

class DownloadNotification extends ObtainiumNotification {
  static const int _baseId = downloadNotificationBaseId;
  DownloadNotification(
    String appName,
    int progPercent, {
    String? appId,
    int? receivedBytes,
    int? totalBytes,
  }) : super(
         _baseId + (appName.hashCode.abs() % downloadNotificationIdRange),
         tr('downloadingX', args: [appName]),
         formatDownloadSize(receivedBytes, totalBytes) ?? '',
         'APP_DOWNLOADING',
         tr('downloadingXNotifChannel', args: [tr('app')]),
         tr('downloadNotifDescription'),
         Importance.low,
         onlyAlertOnce: true,
         progPercent: progPercent,
         androidActions: appId != null
             ? [
                 AndroidNotificationAction(
                   '$cancelDownloadActionPrefix$appId',
                   tr('cancel'),
                   showsUserInterface: false,
                   cancelNotification: true,
                 ),
               ]
             : null,
       );
}

class DownloadedNotification extends ObtainiumNotification {
  DownloadedNotification(String fileName, String downloadUrl)
    : super(
        downloadUrl.hashCode.abs(),
        tr('downloadedX', args: [fileName]),
        '',
        'FILE_DOWNLOADED',
        tr('downloadedXNotifChannel', args: [tr('app')]),
        tr('downloadedX', args: [tr('app')]),
        Importance.defaultImportance,
      );
}

ObtainiumNotification get completeInstallationNotification =>
    ObtainiumNotification(
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

  /// Invoked when the user taps a download notification's Cancel action.
  static void Function(String appId)? onDownloadCancelRequested;

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
    if (isInitialized) return;
    isInitialized =
        await notifications.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('ic_notification'),
          ),
          onDidReceiveNotificationResponse: (NotificationResponse response) {
            final cancelAppId = _cancelActionAppId(response.actionId);
            if (cancelAppId != null) {
              onDownloadCancelRequested?.call(cancelAppId);
              return;
            }
            _showNotificationPayload(response.payload);
          },
          onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
        ) ??
        false;
  }

  /// Called from the main isolate so that download-cancel requests forwarded by
  /// [notificationTapBackground] are received and dispatched to
  /// [onDownloadCancelRequested].
  static void listenForDownloadCancelFromMain() {
    final prevPort = IsolateNameServer.lookupPortByName(
      _downloadCancelPortName,
    );
    if (prevPort != null) {
      IsolateNameServer.removePortNameMapping(_downloadCancelPortName);
    }
    final port = ReceivePort();
    IsolateNameServer.registerPortWithName(
      port.sendPort,
      _downloadCancelPortName,
    );
    port.listen((message) {
      if (message is String && message.isNotEmpty) {
        onDownloadCancelRequested?.call(message);
      }
    });
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
      final lines = payload!.split('\n');
      final title = lines.first;
      final content = lines.sublist(1).join('\n');
      appNavigatorKey.currentState?.push(
        PageRouteBuilder(
          pageBuilder: (context, _, _) => AlertDialog(
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
    await notifications.cancel(id: id);
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
    List<AndroidNotificationAction>? androidActions,
  }) async {
    if (cancelExisting) {
      await cancel(id);
    }
    if (!isInitialized) {
      await initialize();
    }
    await notifications.show(
      id: id,
      title: title,
      body: message,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelCode,
          channelName,
          channelDescription: channelDescription,
          importance: importance,
          priority:
              importanceToPriority[importance] ?? Priority.defaultPriority,
          groupKey: '$obtainiumId.$channelCode',
          progress: progPercent ?? 0,
          maxProgress: 100,
          showProgress: progPercent != null,
          onlyAlertOnce: onlyAlertOnce,
          indeterminate: progPercent != null && progPercent < 0,
          actions: androidActions,
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
    androidActions: notif.androidActions,
  );
}
