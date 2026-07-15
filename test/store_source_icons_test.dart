import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/store_source_icons.dart';

void main() {
  test('fixed source hosts resolve to bundled icons', () {
    final expectedAssetByHost = <String, String>{
      'play.google.com': StoreSourceIconPaths.playStore,
      'github.com': StoreSourceIconPaths.github,
      'gitlab.com': StoreSourceIconPaths.gitlab,
      'codeberg.org': StoreSourceIconPaths.codeberg,
      'f-droid.org': StoreSourceIconPaths.fdroid,
      'izzysoft.de': StoreSourceIconPaths.izzydroid,
      'git.sr.ht': StoreSourceIconPaths.sourcehut,
      'sourceforge.net': StoreSourceIconPaths.sourceforge,
      'itch.io': StoreSourceIconPaths.itchio,
      'example.itch.io': StoreSourceIconPaths.itchio,
      'apkpure.net': StoreSourceIconPaths.apkpure,
      'apkpure.com': StoreSourceIconPaths.apkpure,
      'apkmirror.com': StoreSourceIconPaths.apkmirror,
      'apkcombo.com': StoreSourceIconPaths.apkcombo,
      'aptoide.com': StoreSourceIconPaths.aptoide,
      'uptodown.com': StoreSourceIconPaths.uptodown,
      'appgallery.huawei.com': StoreSourceIconPaths.huaweiAppGallery,
      'appgallery.cloud.huawei.com': StoreSourceIconPaths.huaweiAppGallery,
      'sj.qq.com': StoreSourceIconPaths.tencent,
      'h5.appstore.vivo.com.cn': StoreSourceIconPaths.vivoAppStore,
      'h5coml.vivo.com.cn': StoreSourceIconPaths.vivoAppStore,
      'rustore.ru': StoreSourceIconPaths.rustore,
      'apk4free.net': StoreSourceIconPaths.apk4free,
      'farsroid.com': StoreSourceIconPaths.farsroid,
      'www.coolapk.com': StoreSourceIconPaths.coolapk,
      'api2.coolapk.com': StoreSourceIconPaths.coolapk,
      'rockmods.net': StoreSourceIconPaths.rockmods,
      'liteapks.com': StoreSourceIconPaths.liteapks,
      'telegram.org': StoreSourceIconPaths.telegram,
      'mullvad.net': StoreSourceIconPaths.mullvad,
    };

    for (final entry in expectedAssetByHost.entries) {
      final assetPath = storeSourceAssetPathForHost(entry.key);
      expect(assetPath, entry.value, reason: entry.key);
      expect(File(assetPath!).existsSync(), isTrue, reason: assetPath);
      if (assetPath.endsWith('.svg')) {
        final svgContent = File(assetPath).readAsStringSync();
        expect(svgContent.contains('<svg'), isTrue, reason: assetPath);
        expect(
          RegExp(r'viewBox\s*=').hasMatch(svgContent),
          isTrue,
          reason: assetPath,
        );
        expect(
          RegExp(r'<image\b', caseSensitive: false).hasMatch(svgContent),
          isFalse,
          reason: assetPath,
        );
      } else {
        expect(assetPath, endsWith('.png'), reason: assetPath);
        final dimensions = _pngDimensions(File(assetPath));
        expect(dimensions.$1, greaterThanOrEqualTo(160), reason: assetPath);
        expect(dimensions.$2, greaterThanOrEqualTo(160), reason: assetPath);
      }
    }

    for (final assetPath in <String>[
      StoreSourceIconPaths.apkpure,
      StoreSourceIconPaths.liteapks,
      StoreSourceIconPaths.vivoAppStore,
    ]) {
      expect(assetPath, endsWith('.png'), reason: assetPath);
    }

    expect(
      storeSourceAssetPathForClassName('ItchIO'),
      StoreSourceIconPaths.itchio,
    );
  });

  test('custom hosts do not resolve to bundled icons', () {
    expect(storeSourceAssetPathForHost('example.com'), isNull);
    expect(storeSourceAssetPathForHost('neutroncode.com'), isNull);
    expect(storeSourceAssetPathForClassName('NeutronCode'), isNull);
  });

  test('black source marks invert only in dark mode', () {
    expect(iconNeedsInversion(StoreSourceIconPaths.github, true), isTrue);
    expect(iconNeedsInversion(StoreSourceIconPaths.sourcehut, true), isTrue);
    expect(iconNeedsInversion(StoreSourceIconPaths.github, false), isFalse);
    expect(iconNeedsInversion(StoreSourceIconPaths.apkmirror, true), isFalse);
    expect(iconNeedsInversion(StoreSourceIconPaths.apkmirror, false), isFalse);
  });
}

(int, int) _pngDimensions(File file) {
  final bytes = file.readAsBytesSync();
  expect(
    bytes.sublist(0, 8),
    orderedEquals(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
    reason: file.path,
  );
  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}
