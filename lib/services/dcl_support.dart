import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

typedef _MmapNative =
    Pointer<Void> Function(
      Pointer<Void> address,
      Size length,
      Int32 protection,
      Int32 flags,
      Int32 fd,
      Long offset,
    );

typedef _MmapDart =
    Pointer<Void> Function(
      Pointer<Void> address,
      int length,
      int protection,
      int flags,
      int fd,
      int offset,
    );

typedef _MunmapNative = Int32 Function(Pointer<Void> address, Size length);

typedef _MunmapDart = int Function(Pointer<Void> address, int length);

class DclSupport {
  DclSupport._();

  static const int _denyExecmem = 1;
  static const int _probeLength = 4096;
  static const int _protRead = 0x1;
  static const int _protExec = 0x4;
  static const int _mapPrivate = 0x2;
  static const int _mapAnonymous = 0x20;
  static const List<String> _procAttrPaths = [
    '/proc/self/attr/grapheneos_flags',
    '/proc/self/attr/selinux_flags',
  ];

  static bool? _cachedRestricted;

  @visibleForTesting
  static String? Function(String path)? debugReadFile;

  @visibleForTesting
  static bool Function()? debugProbeExecmem;

  static bool get isExecmemRestricted {
    return _cachedRestricted ??= _detect();
  }

  static void resetCache() {
    _cachedRestricted = null;
  }

  static bool _detect() {
    if (!Platform.isAndroid &&
        debugReadFile == null &&
        debugProbeExecmem == null) {
      return false;
    }
    for (final path in _procAttrPaths) {
      final value = _readFile(path);
      if (value == null) continue;
      final flags = int.tryParse(value.trim(), radix: 16);
      if (flags != null) {
        return (flags & _denyExecmem) != 0;
      }
    }
    return (debugProbeExecmem ?? _probeExecmem)();
  }

  static String? _readFile(String path) {
    final reader = debugReadFile;
    if (reader != null) return reader(path);
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      return file.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  static bool _probeExecmem() {
    if (!Platform.isAndroid && !Platform.isLinux) return false;
    try {
      final process = DynamicLibrary.process();
      final mmap = process.lookupFunction<_MmapNative, _MmapDart>(
        'mmap',
        isLeaf: true,
      );
      final munmap = process.lookupFunction<_MunmapNative, _MunmapDart>(
        'munmap',
        isLeaf: true,
      );
      final mapping = mmap(
        nullptr,
        _probeLength,
        _protRead | _protExec,
        _mapPrivate | _mapAnonymous,
        -1,
        0,
      );
      if (mapping.address == -1) return true;
      munmap(mapping, _probeLength);
      return false;
    } catch (_) {
      return false;
    }
  }
}
