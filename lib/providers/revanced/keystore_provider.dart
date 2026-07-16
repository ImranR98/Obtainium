// Manages Obtainium's ReVanced signing keystore: native generation/import/export,
// plus the alias/password metadata needed to use it. Not part of AppsProvider
// since it's independent of any specific tracked app (per the "standalone
// keystore import/export" requirement).

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/settings_provider.dart';

const String _channelName = 'dev.imranr.obtainium/revanced';
const String kKeystoreAliasKey = 'revanced-keystore-alias';
// Suffixed with "-creds" so it's automatically stripped from general export
// whenever exportSettings < 2, same convention as e.g. 'github-creds'.
const String kKeystorePasswordKey = 'revanced-keystore-pass-creds';

class KeystoreProvider with ChangeNotifier {
  KeystoreProvider({SettingsProvider? settingsProvider, MethodChannel? channel})
    : _settingsProvider = settingsProvider,
      _channel = channel ?? const MethodChannel(_channelName);

  final SettingsProvider? _settingsProvider;
  final MethodChannel _channel;

  SettingsProvider get _settings => _settingsProvider ?? SettingsProvider();

  String get alias =>
      _settings.getSettingString(kKeystoreAliasKey) ?? 'Obtainium';
  String get password =>
      _settings.getSettingString(kKeystorePasswordKey) ?? 'Obtainium';

  Future<bool> hasKeystore() async {
    try {
      return await _channel.invokeMethod<bool>('hasKeystore') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Generates a new keystore, overwriting any existing one. Callers should
  /// warn the user that this breaks future updates to already-patched apps.
  Future<void> regenerate({String? alias, String? password}) async {
    final a = alias ?? this.alias;
    final p = password ?? this.password;
    try {
      await _channel.invokeMethod('regenerateKeystore', {
        'alias': a,
        'password': p,
      });
    } on PlatformException catch (e) {
      throw ObtainiumError(e.message ?? 'Failed to generate keystore');
    }
    _settings.setSettingString(kKeystoreAliasKey, a);
    _settings.setSettingString(kKeystorePasswordKey, p);
    notifyListeners();
  }

  /// Validates and imports a user-supplied keystore. Returns false (without
  /// changing anything) if the alias/password don't unlock a usable key.
  Future<bool> importFromBytes(
    Uint8List bytes, {
    required String alias,
    required String password,
  }) async {
    bool ok;
    try {
      ok =
          await _channel.invokeMethod<bool>('importKeystore', {
            'alias': alias,
            'password': password,
            'bytes': bytes,
          }) ??
          false;
    } on PlatformException catch (e) {
      throw ObtainiumError(e.message ?? 'Failed to import keystore');
    }
    if (ok) {
      _settings.setSettingString(kKeystoreAliasKey, alias);
      _settings.setSettingString(kKeystorePasswordKey, password);
      notifyListeners();
    }
    return ok;
  }

  /// Returns the raw keystore bytes, or null if none exists yet.
  Future<Uint8List?> exportToBytes() async {
    try {
      final result = await _channel.invokeMethod<Uint8List>('exportKeystore');
      return result;
    } on PlatformException catch (e) {
      throw ObtainiumError(e.message ?? 'Failed to export keystore');
    }
  }
}
