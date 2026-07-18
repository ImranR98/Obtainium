import 'package:flutter/material.dart';

/// Formats a numeric date using the device locale's month/day order and omits
/// the year when [dateTime] falls within the current year.
String formatDeviceOrderedNumericDate(
  BuildContext context,
  DateTime dateTime, {
  DateTime? now,
}) {
  final DateTime local = dateTime.toLocal();
  final DateTime localNow = (now ?? DateTime.now()).toLocal();
  final String datePattern = MaterialLocalizations.of(
    context,
  ).dateHelpText.toLowerCase();
  final int monthPosition = datePattern.indexOf('m');
  final int dayPosition = datePattern.indexOf('d');
  final bool monthComesFirst =
      monthPosition < 0 || dayPosition < 0 || monthPosition < dayPosition;
  final String month = local.month.toString().padLeft(2, '0');
  final String day = local.day.toString().padLeft(2, '0');
  final String monthAndDay = monthComesFirst ? '$month-$day' : '$day-$month';
  return local.year == localNow.year
      ? monthAndDay
      : '${local.year}-$monthAndDay';
}
