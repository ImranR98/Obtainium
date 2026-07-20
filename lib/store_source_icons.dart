import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:obtainium/favicon_cache.dart';

/// Inversion filter: swaps black ↔ white while preserving alpha.
const ColorFilter invertColorFilter = ColorFilter.matrix([
  -1,
  0,
  0,
  0,
  255,
  0,
  -1,
  0,
  0,
  255,
  0,
  0,
  -1,
  0,
  255,
  0,
  0,
  0,
  1,
  0,
]);

/// Returns true if [assetPath]'s icon should be colour-inverted for the current
/// brightness. GitHub and SourceHut ship black marks, so they need inversion
/// in dark mode.
bool iconNeedsInversion(String assetPath, bool isDark) {
  return isDark &&
      (assetPath == StoreSourceIconPaths.github ||
          assetPath == StoreSourceIconPaths.sourcehut);
}

/// Logo widget for store chips: bundled asset for known hosts, favicon for others.
/// Suitable as a [FilterChip] avatar — transparent background, no container border.
class StoreSourceChipAvatar extends StatefulWidget {
  const StoreSourceChipAvatar({super.key, required this.host, this.size = 18});

  final String host;
  final double size;

  @override
  State<StoreSourceChipAvatar> createState() => _StoreSourceChipAvatarState();
}

class _StoreSourceChipAvatarState extends State<StoreSourceChipAvatar> {
  Future<Uint8List?>? _iconFuture;

  @override
  void initState() {
    super.initState();
    if (widget.host.isNotEmpty &&
        storeSourceAssetPathForHost(widget.host) == null) {
      _iconFuture = FaviconCache.get(widget.host);
    }
  }

  @override
  void didUpdateWidget(StoreSourceChipAvatar old) {
    super.didUpdateWidget(old);
    if (old.host != widget.host &&
        widget.host.isNotEmpty &&
        storeSourceAssetPathForHost(widget.host) == null) {
      setState(() => _iconFuture = FaviconCache.get(widget.host));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.host.isEmpty) {
      return SizedBox(width: widget.size, height: widget.size);
    }

    final String? localAsset = storeSourceAssetPathForHost(widget.host);
    if (localAsset != null) {
      return StoreSourceIconImage(assetPath: localAsset, size: widget.size);
    }

    return FutureBuilder<Uint8List?>(
      future: _iconFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            snapshot.data == null) {
          return SizedBox(width: widget.size, height: widget.size);
        }
        final int cachePx =
            (widget.size * MediaQuery.devicePixelRatioOf(context)).round();
        return Image.memory(
          snapshot.data!,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          cacheWidth: cachePx,
          cacheHeight: cachePx,
        );
      },
    );
  }
}

/// Local asset paths for store branding (list badges, app page source rows).
class StoreSourceIconPaths {
  StoreSourceIconPaths._();

  static const String playStore = 'assets/graphics/ic_playstore.svg';
  static const String fdroid = 'assets/graphics/ic_fdroid.svg';
  static const String apkmirror = 'assets/graphics/ic_apkmirror.svg';
  static const String apkpure = 'assets/graphics/ic_apkpure.png';
  static const String github = 'assets/graphics/ic_github.svg';
  static const String gitlab = 'assets/graphics/ic_gitlab.svg';
  static const String codeberg = 'assets/graphics/ic_codeberg.svg';
  static const String sourcehut = 'assets/graphics/ic_sourcehut.svg';
  static const String sourceforge = 'assets/graphics/ic_sourceforge.svg';
  static const String itchio = 'assets/graphics/ic_itchio.svg';
  static const String apkcombo = 'assets/graphics/ic_apkcombo.svg';
  static const String aptoide = 'assets/graphics/ic_aptoide.svg';
  static const String uptodown = 'assets/graphics/ic_uptodown.svg';
  static const String huaweiAppGallery =
      'assets/graphics/ic_huaweiappgallery.svg';
  static const String tencent = 'assets/graphics/ic_tencent.svg';
  static const String vivoAppStore = 'assets/graphics/ic_vivoappstore.png';
  static const String rustore = 'assets/graphics/ic_rustore.svg';
  static const String apk4free = 'assets/graphics/ic_apk4free.svg';
  static const String farsroid = 'assets/graphics/ic_farsroid.svg';
  static const String coolapk = 'assets/graphics/ic_coolapk.svg';
  static const String rockmods = 'assets/graphics/ic_rockmods.svg';
  static const String liteapks = 'assets/graphics/ic_liteapks.png';
  static const String telegram = 'assets/graphics/ic_telegram.svg';
  static const String mullvad = 'assets/graphics/ic_mullvad.svg';
  static const String izzydroid = 'assets/graphics/ic_izzydroid.svg';
}

/// Maps a source [host] (e.g. from [SourceProvider]) to a bundled icon, or null.
String? storeSourceAssetPathForHost(String host) {
  final String normalized = host.toLowerCase();
  if (normalized.contains('play.google.com')) {
    return StoreSourceIconPaths.playStore;
  }
  if (normalized.contains('f-droid.org')) {
    return StoreSourceIconPaths.fdroid;
  }
  if (normalized.contains('apkmirror.com')) {
    return StoreSourceIconPaths.apkmirror;
  }
  if (normalized.contains('apkpure.')) {
    return StoreSourceIconPaths.apkpure;
  }
  if (normalized.contains('github.com')) {
    return StoreSourceIconPaths.github;
  }
  if (normalized.contains('gitlab.com')) {
    return StoreSourceIconPaths.gitlab;
  }
  if (normalized.contains('codeberg.org')) {
    return StoreSourceIconPaths.codeberg;
  }
  if (normalized.contains('izzysoft.de')) {
    return StoreSourceIconPaths.izzydroid;
  }
  if (normalized.contains('git.sr.ht')) {
    return StoreSourceIconPaths.sourcehut;
  }
  if (normalized.contains('sourceforge.net')) {
    return StoreSourceIconPaths.sourceforge;
  }
  if (normalized.contains('itch.io')) {
    return StoreSourceIconPaths.itchio;
  }
  if (normalized.contains('apkcombo.com')) {
    return StoreSourceIconPaths.apkcombo;
  }
  if (normalized.contains('aptoide.com')) {
    return StoreSourceIconPaths.aptoide;
  }
  if (normalized.contains('uptodown.com')) {
    return StoreSourceIconPaths.uptodown;
  }
  if (normalized.contains('appgallery.huawei.com') ||
      normalized.contains('appgallery.cloud.huawei.com')) {
    return StoreSourceIconPaths.huaweiAppGallery;
  }
  if (normalized.contains('sj.qq.com')) {
    return StoreSourceIconPaths.tencent;
  }
  if (normalized.contains('h5.appstore.vivo.com.cn') ||
      normalized.contains('h5coml.vivo.com.cn')) {
    return StoreSourceIconPaths.vivoAppStore;
  }
  if (normalized.contains('rustore.ru')) {
    return StoreSourceIconPaths.rustore;
  }
  if (normalized.contains('apk4free.net')) {
    return StoreSourceIconPaths.apk4free;
  }
  if (normalized.contains('farsroid.com')) {
    return StoreSourceIconPaths.farsroid;
  }
  if (normalized.contains('coolapk.com')) {
    return StoreSourceIconPaths.coolapk;
  }
  if (normalized.contains('rockmods.net')) {
    return StoreSourceIconPaths.rockmods;
  }
  if (normalized.contains('liteapks.com')) {
    return StoreSourceIconPaths.liteapks;
  }
  if (normalized.contains('telegram.org')) {
    return StoreSourceIconPaths.telegram;
  }
  if (normalized.contains('mullvad.net')) {
    return StoreSourceIconPaths.mullvad;
  }
  return null;
}

/// Maps a full [url] (tracked source, etc.) to the same bundled icon, or null.
String? storeSourceAssetPathForUrl(String url) {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  return storeSourceAssetPathForHost(uri.host);
}

/// Maps an [AppSource] runtimeType class name to a bundled icon path, or null.
/// Use [storeSourceAssetPathForHost] when a URL or host is available instead.
String? storeSourceAssetPathForClassName(String className) {
  switch (className) {
    case 'GitHub':
      return StoreSourceIconPaths.github;
    case 'GitLab':
      return StoreSourceIconPaths.gitlab;
    case 'Codeberg':
      return StoreSourceIconPaths.codeberg;
    case 'FDroid':
      return StoreSourceIconPaths.fdroid;
    case 'APKMirror':
      return StoreSourceIconPaths.apkmirror;
    case 'APKPure':
      return StoreSourceIconPaths.apkpure;
    case 'IzzyOnDroid':
      return StoreSourceIconPaths.izzydroid;
    case 'SourceHut':
      return StoreSourceIconPaths.sourcehut;
    case 'SourceForge':
      return StoreSourceIconPaths.sourceforge;
    case 'ItchIO':
      return StoreSourceIconPaths.itchio;
    case 'APKCombo':
      return StoreSourceIconPaths.apkcombo;
    case 'Aptoide':
      return StoreSourceIconPaths.aptoide;
    case 'Uptodown':
      return StoreSourceIconPaths.uptodown;
    case 'HuaweiAppGallery':
      return StoreSourceIconPaths.huaweiAppGallery;
    case 'Tencent':
      return StoreSourceIconPaths.tencent;
    case 'VivoAppStore':
      return StoreSourceIconPaths.vivoAppStore;
    case 'RuStore':
      return StoreSourceIconPaths.rustore;
    case 'Apk4Free':
      return StoreSourceIconPaths.apk4free;
    case 'Farsroid':
      return StoreSourceIconPaths.farsroid;
    case 'CoolApk':
      return StoreSourceIconPaths.coolapk;
    case 'RockMods':
      return StoreSourceIconPaths.rockmods;
    case 'LiteAPKs':
      return StoreSourceIconPaths.liteapks;
    case 'TelegramApp':
      return StoreSourceIconPaths.telegram;
    case 'Mullvad':
      return StoreSourceIconPaths.mullvad;
    default:
      return null;
  }
}

/// Bundled source icon rendered at a fixed logical size.
class StoreSourceIconImage extends StatelessWidget {
  const StoreSourceIconImage({
    super.key,
    required this.assetPath,
    required this.size,
    this.errorBuilder,
  });

  final String assetPath;
  final double size;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    if (assetPath.endsWith('.svg')) {
      return SizedBox.square(
        dimension: size,
        child: SvgPicture.asset(
          assetPath,
          fit: BoxFit.contain,
          clipBehavior: Clip.antiAlias,
          colorFilter: iconNeedsInversion(assetPath, isDark)
              ? invertColorFilter
              : null,
          errorBuilder: (BuildContext context, Object error, StackTrace stack) {
            return errorBuilder?.call(context, error, stack) ??
                _buildError(context);
          },
        ),
      );
    }

    final int cachePx = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final Widget image = Image.asset(
      assetPath,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      cacheWidth: cachePx,
      cacheHeight: cachePx,
      errorBuilder:
          (BuildContext context, Object error, StackTrace? stackTrace) {
            return errorBuilder?.call(context, error, stackTrace) ??
                _buildError(context);
          },
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: SizedBox(width: size, height: size, child: image),
    );
  }

  Widget _buildError(BuildContext context) {
    if (size <= 20) {
      return const SizedBox.shrink();
    }
    return Icon(
      Icons.link,
      size: size * 0.72,
      color: Theme.of(context).colorScheme.primary,
    );
  }
}

/// Icon for a tracked source URL: bundled asset for known hosts, fetched
/// favicon for unknown hosts, [Icons.link] if neither resolves.
class StoreSourceIconForUrl extends StatefulWidget {
  const StoreSourceIconForUrl({
    super.key,
    required this.url,
    required this.size,
  });

  final String url;
  final double size;

  @override
  State<StoreSourceIconForUrl> createState() => _StoreSourceIconForUrlState();
}

class _StoreSourceIconForUrlState extends State<StoreSourceIconForUrl> {
  Future<Uint8List?>? _iconFuture;
  late final String _host;

  @override
  void initState() {
    super.initState();
    _host = Uri.tryParse(widget.url)?.host ?? '';
    if (_host.isNotEmpty && storeSourceAssetPathForHost(_host) == null) {
      _iconFuture = FaviconCache.get(_host);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? localAsset = storeSourceAssetPathForHost(_host);
    if (localAsset != null) {
      return StoreSourceIconImage(assetPath: localAsset, size: widget.size);
    }
    return FutureBuilder<Uint8List?>(
      future: _iconFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data != null) {
          final int cachePx =
              (widget.size * MediaQuery.devicePixelRatioOf(context)).round();
          return Image.memory(
            snapshot.data!,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            cacheWidth: cachePx,
            cacheHeight: cachePx,
          );
        }
        return Icon(
          Icons.link,
          size: widget.size * 0.75,
          color: Theme.of(context).colorScheme.primary,
        );
      },
    );
  }
}

/// Small source favicon badge overlaid on the app icon (Apps list, bulk import results).
/// Known hosts use bundled assets; unknown hosts use a persistent disk-cached
/// direct favicon first, with DuckDuckGo fallback only when the build allows it.
class StoreSourceListBadge extends StatefulWidget {
  const StoreSourceListBadge({super.key, required this.host});

  final String host;

  @override
  State<StoreSourceListBadge> createState() => _StoreSourceListBadgeState();
}

class _StoreSourceListBadgeState extends State<StoreSourceListBadge> {
  Future<Uint8List?>? _iconFuture;

  @override
  void initState() {
    super.initState();
    if (widget.host.isNotEmpty &&
        storeSourceAssetPathForHost(widget.host) == null) {
      _iconFuture = FaviconCache.get(widget.host);
    }
  }

  @override
  void didUpdateWidget(StoreSourceListBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host &&
        widget.host.isNotEmpty &&
        storeSourceAssetPathForHost(widget.host) == null) {
      _iconFuture = FaviconCache.get(widget.host);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.host.isEmpty) return const SizedBox.shrink();

    final String? localAsset = storeSourceAssetPathForHost(widget.host);

    Widget image;
    if (localAsset != null) {
      image = StoreSourceIconImage(assetPath: localAsset, size: 13);
    } else {
      image = FutureBuilder<Uint8List?>(
        future: _iconFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done ||
              snapshot.data == null) {
            return const SizedBox.shrink();
          }
          final int cachePx = (13 * MediaQuery.devicePixelRatioOf(context))
              .round();
          return Image.memory(
            snapshot.data!,
            width: 13,
            height: 13,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            cacheWidth: cachePx,
            cacheHeight: cachePx,
          );
        },
      );
    }

    return SizedBox(
      width: 16,
      height: 16,
      child: Padding(padding: const EdgeInsets.all(1.5), child: image),
    );
  }
}
