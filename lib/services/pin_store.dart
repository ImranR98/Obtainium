import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/services/pinned_certificates.dart';
import 'package:path_provider/path_provider.dart';

class ResolvedPinSet {
  final String id;
  final int revision;
  final List<PinnedCertificate> certificates;
  final bool builtIn;

  const ResolvedPinSet({
    required this.id,
    required this.revision,
    required this.certificates,
    required this.builtIn,
  });
}

class PinStore extends ChangeNotifier {
  PinStore._({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  @visibleForTesting
  PinStore.forTesting(Future<Directory> Function() directoryProvider)
    : _directoryProvider = directoryProvider;

  static final PinStore instance = PinStore._();

  static const String _fileName = 'pinned_certificates.json';
  static const int _schemaVersion = 1;

  final Future<Directory> Function() _directoryProvider;

  bool _loaded = false;
  Future<void>? _loading;
  Object? _loadError;
  int _revision = 0;
  List<UserPinSet> _userSets = [];
  Set<String> _disabledBuiltInHosts = {};
  Map<String, Set<String>> _disabledBuiltInCerts = {};

  bool get loaded => _loaded;
  Object? get loadError => _loadError;
  int get revision => _revision;
  List<UserPinSet> get userSets => List.unmodifiable(_userSets);
  bool get hasBuiltInOverrides =>
      _disabledBuiltInHosts.isNotEmpty ||
      _disabledBuiltInCerts.values.any((certs) => certs.isNotEmpty);

  bool builtInHostEnabled(String host) => !_disabledBuiltInHosts.contains(host);

  bool builtInCertEnabled(String host, PinnedCertificate certificate) =>
      !(_disabledBuiltInCerts[host]?.contains(certificate.sha256) ?? false);

  List<PinnedCertificate> enabledBuiltInCertificates(BuiltInPinnedHost host) =>
      [
        for (final certificate in host.certificates)
          if (builtInCertEnabled(host.host, certificate)) certificate,
      ];

  BuiltInPinnedHost? builtInHostFor(String host) {
    for (final builtIn in builtInPinnedHosts) {
      if (_hostMatches(builtIn.host, builtIn.includeSubdomains, host)) {
        return builtIn;
      }
    }
    return null;
  }

  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    File? file;
    try {
      final directory = await _directoryProvider();
      file = File('${directory.path}/$_fileName');
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) {
          throw ObtainiumError(tr('pinStoreInvalidFormat'));
        }
        _readJson(Map<String, dynamic>.from(decoded));
      }
    } catch (e, stackTrace) {
      _loadError = e;
      AppLogger.error(
        e,
        stackTrace: stackTrace,
        message: 'Failed to load pinned certificates',
      );
      if (file != null && await file.exists()) {
        try {
          await file.rename(
            '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}',
          );
        } catch (renameError) {
          AppLogger.warn('Failed to back up corrupt pin store: $renameError');
        }
      }
    } finally {
      _loaded = true;
      _loading = null;
      notifyListeners();
    }
  }

  void _readJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version != _schemaVersion) {
      throw ObtainiumError(
        tr('pinStoreUnsupportedVersion', args: [version.toString()]),
      );
    }
    final sets = <UserPinSet>[];
    for (final raw in (json['userSets'] as List? ?? const [])) {
      try {
        final set = UserPinSet.fromJson(Map<String, dynamic>.from(raw as Map));
        if (set.hosts.isNotEmpty && set.certificates.isNotEmpty) {
          sets.add(set);
        }
      } catch (e) {
        AppLogger.warn('Skipping invalid user pin set: $e');
      }
    }
    final disabledHosts = <String>{};
    for (final host in (json['disabledBuiltInHosts'] as List? ?? const [])) {
      if (host is String && host.isNotEmpty) disabledHosts.add(host);
    }

    final disabledCerts = <String, Set<String>>{};
    final rawDisabledCerts = json['disabledBuiltInCerts'];
    if (rawDisabledCerts is Map) {
      rawDisabledCerts.forEach((key, value) {
        if (key is! String || value is! List) return;
        final fingerprints = value.whereType<String>().toSet();
        if (fingerprints.isNotEmpty) disabledCerts[key] = fingerprints;
      });
    }

    _userSets = sets;
    _disabledBuiltInHosts = disabledHosts;
    _disabledBuiltInCerts = disabledCerts;
  }

  Map<String, dynamic> _toJson() => {
    'version': _schemaVersion,
    'userSets': [for (final set in _userSets) set.toJson()],
    'disabledBuiltInHosts': _disabledBuiltInHosts.toList()..sort(),
    'disabledBuiltInCerts': {
      for (final entry in _disabledBuiltInCerts.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value.toList()..sort(),
    },
  };

  Future<void> _save() async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final file = File('${directory.path}/$_fileName');
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(_toJson()), flush: true);
    await temp.rename(file.path);
  }

  void _changed() {
    _revision++;
    notifyListeners();
  }

  Future<void> addUserSet(UserPinSet set) async {
    await ensureLoaded();
    validateUserSet(set);
    if (_userSets.any((existing) => existing.id == set.id)) {
      throw ArgumentError(tr('pinSetIdExists'));
    }
    _userSets = [..._userSets, set];
    _changed();
    await _save();
  }

  Future<void> updateUserSet(UserPinSet set) async {
    await ensureLoaded();
    validateUserSet(set, ignoreId: set.id);
    final index = _userSets.indexWhere((existing) => existing.id == set.id);
    if (index < 0) throw ArgumentError(tr('pinSetNotFound'));
    _userSets = [..._userSets]..[index] = set;
    _changed();
    await _save();
  }

  Future<void> deleteUserSet(String id) async {
    await ensureLoaded();
    _userSets = _userSets.where((set) => set.id != id).toList();
    _changed();
    await _save();
  }

  Future<void> setBuiltInHostEnabled(String host, bool enabled) async {
    await ensureLoaded();
    if (enabled) {
      _disabledBuiltInHosts.remove(host);
    } else {
      _disabledBuiltInHosts.add(host);
    }
    _changed();
    await _save();
  }

  Future<void> setBuiltInCertEnabled(
    String host,
    String sha256,
    bool enabled,
  ) async {
    await ensureLoaded();
    final disabled = _disabledBuiltInCerts.putIfAbsent(host, () => <String>{});
    if (enabled) {
      disabled.remove(sha256);
      if (disabled.isEmpty) _disabledBuiltInCerts.remove(host);
    } else {
      disabled.add(sha256);
    }
    _changed();
    await _save();
  }

  Future<void> restoreBuiltInHost(String host) async {
    await ensureLoaded();
    _disabledBuiltInHosts.remove(host);
    _disabledBuiltInCerts.remove(host);
    _changed();
    await _save();
  }

  Future<void> restoreAllBuiltIn() async {
    await ensureLoaded();
    _disabledBuiltInHosts.clear();
    _disabledBuiltInCerts.clear();
    _changed();
    await _save();
  }

  ResolvedPinSet? resolve(String host) {
    final normalizedHost = host.toLowerCase();
    _PinCandidate? best;
    for (final set in _userSets) {
      if (set.certificates.isEmpty) continue;
      for (final rule in set.hosts) {
        if (!rule.matches(normalizedHost)) continue;
        final candidate = _PinCandidate(
          id: set.id,
          score: rule.specificity,
          builtIn: false,
          certificates: set.certificates,
        );
        if (best == null ||
            candidate.score > best.score ||
            (candidate.score == best.score &&
                !candidate.builtIn &&
                best.builtIn)) {
          best = candidate;
        }
      }
    }
    for (final builtIn in builtInPinnedHosts) {
      if (!_hostMatches(
        builtIn.host,
        builtIn.includeSubdomains,
        normalizedHost,
      )) {
        continue;
      }
      if (!builtInHostEnabled(builtIn.host)) continue;
      final certificates = enabledBuiltInCertificates(builtIn);
      if (certificates.isEmpty) continue;
      final candidate = _PinCandidate(
        id: 'builtin:${builtIn.host}',
        score: builtIn.host.length,
        builtIn: true,
        certificates: certificates,
      );
      if (best == null ||
          candidate.score > best.score ||
          (candidate.score == best.score && best.builtIn)) {
        best = candidate;
      }
    }
    if (best == null) return null;
    return ResolvedPinSet(
      id: best.id,
      revision: _revision,
      certificates: best.certificates,
      builtIn: best.builtIn,
    );
  }

  List<UserPinSet> overlappingUserSets(String host, {String? ignoreId}) => [
    for (final set in _userSets)
      if (set.id != ignoreId && set.hosts.any((rule) => rule.matches(host)))
        set,
  ];

  /// Throws when [set] is internally invalid or ambiguously overlaps another
  /// user pin set.
  void validateUserSet(UserPinSet set, {String? ignoreId}) {
    if (set.hosts.isEmpty) {
      throw ArgumentError(tr('pinSetNeedsHost'));
    }
    if (set.certificates.isEmpty) {
      throw ArgumentError(tr('pinSetNeedsCertificate'));
    }
    final seenHosts = <String>{};
    for (final rule in set.hosts) {
      if (rule.host.trim().isEmpty) {
        throw ArgumentError(tr('invalidHost'));
      }
      final key = '${rule.host}|${rule.includeSubdomains}';
      if (!seenHosts.add(key)) {
        throw ArgumentError(tr('duplicateHost', args: [rule.host]));
      }
    }
    for (final other in _userSets) {
      if (other.id == ignoreId) continue;
      for (final ownRule in set.hosts) {
        for (final otherRule in other.hosts) {
          if (!_rulesOverlap(ownRule, otherRule)) continue;
          if (ownRule.specificity == otherRule.specificity) {
            throw ArgumentError(tr('pinSetHostOverlap', args: [ownRule.host]));
          }
        }
      }
    }
  }

  bool _rulesOverlap(PinHostRule a, PinHostRule b) =>
      a.matches(b.host) || b.matches(a.host);

  static bool _hostMatches(
    String ruleHost,
    bool includeSubdomains,
    String requestHost,
  ) =>
      requestHost == ruleHost ||
      (includeSubdomains && requestHost.endsWith('.$ruleHost'));
}

class _PinCandidate {
  final String id;
  final int score;
  final bool builtIn;
  final List<PinnedCertificate> certificates;

  const _PinCandidate({
    required this.id,
    required this.score,
    required this.builtIn,
    required this.certificates,
  });
}
