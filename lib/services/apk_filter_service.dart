// APK file detection, filtering, and architecture selection.

import 'package:device_info_plus/device_info_plus.dart';

// ========================================================================
// ApkFilterService — APK file detection, filtering, and arch-splitting.
// ========================================================================

class ApkFilterService {
  static const List<String> apkContainerExtensions = [
    '.apk',
    '.xapk',
    '.apkm',
    '.apks',
  ];

  static const List<String> archiveExtensions = ['.zip'];

  static const List<String> tarballExtensions = [
    '.tar.gz',
    '.tgz',
    '.tar.bz2',
    '.tar.xz',
  ];

  static bool isApkOrContainerFile(
    String name, {
    bool includeArchives = false,
    bool includeTarballs = false,
  }) {
    final lower = name.toLowerCase();
    bool endsWithAny(List<String> exts) => exts.any(lower.endsWith);
    return endsWithAny(apkContainerExtensions) ||
        (includeArchives && endsWithAny(archiveExtensions)) ||
        (includeTarballs && endsWithAny(tarballExtensions));
  }

  List<MapEntry<String, String>> getApkUrlsFromUrls(List<String> urls) =>
      urls.map((e) {
        final segments = e.split('/').where((el) => el.trim().isNotEmpty);
        final apkSegs = segments.where((s) => isApkOrContainerFile(s));
        return MapEntry(apkSegs.isNotEmpty ? apkSegs.last : segments.last, e);
      }).toList();

  List<MapEntry<String, String>> filterApks(
    List<MapEntry<String, String>> apkUrls,
    String? apkFilterRegEx,
    bool? invert,
  ) {
    if (apkFilterRegEx?.isNotEmpty == true) {
      final reg = RegExp(apkFilterRegEx!);
      apkUrls = apkUrls.where((element) {
        final hasMatch = reg.hasMatch(element.key);
        return invert == true ? !hasMatch : hasMatch;
      }).toList();
    }
    return apkUrls;
  }

  /// Non-canonical ABI names commonly used in APK filenames, mapped to the
  /// canonical device ABI strings they correspond to (see #3249).
  static const Map<String, List<String>> abiNameAliases = {
    'arm64-v8a': ['aarch64', 'arm64'],
    'armeabi-v7a': ['armv7', 'armeabi'],
    'x86_64': ['x64'],
  };

  Future<List<MapEntry<String, String>>> filterApksByArch(
    List<MapEntry<String, String>> apkUrls,
    List<String> abis,
  ) async {
    if (apkUrls.length > 1) {
      for (var abi in abis) {
        final variants = [abi, ...?abiNameAliases[abi]];
        final abiRegex = RegExp(
          '.*(?:${variants.join('|')}).*',
          caseSensitive: false,
        );
        final urls2 = apkUrls
            .where((element) => abiRegex.hasMatch(element.key))
            .toList();
        if (urls2.isNotEmpty && urls2.length < apkUrls.length) {
          apkUrls = urls2;
          break;
        }
      }
    }
    return apkUrls;
  }
}

/// Delegates to [ApkFilterService.getApkUrlsFromUrls].
List<MapEntry<String, String>> getApkUrlsFromUrls(List<String> urls) =>
    ApkFilterService().getApkUrlsFromUrls(urls);

/// Delegates to [ApkFilterService.filterApksByArch].
Future<List<MapEntry<String, String>>> filterApksByArch(
  List<MapEntry<String, String>> apkUrls,
) async {
  final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
  return ApkFilterService().filterApksByArch(apkUrls, abis);
}

/// Delegates to [ApkFilterService.filterApks].
List<MapEntry<String, String>> filterApks(
  List<MapEntry<String, String>> apkUrls,
  String? apkFilterRegEx,
  bool? invert,
) => ApkFilterService().filterApks(apkUrls, apkFilterRegEx, invert);
