// Standalone keystore management UI: generate/import/export the keystore used
// to sign ReVanced-patched APKs, independent of the general Obtainium
// import/export flow (which separately bundles the keystore only when
// "include settings" is set to "all" - see apps_provider_import_export.dart).

import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/revanced/keystore_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_storage/shared_storage.dart' as saf;

class KeystoreSection extends StatefulWidget {
  const KeystoreSection({super.key});

  @override
  State<KeystoreSection> createState() => _KeystoreSectionState();
}

class _KeystoreSectionState extends State<KeystoreSection> {
  bool _busy = false;
  Future<bool>? _hasKeystoreFuture;

  KeystoreProvider _provider(BuildContext context) =>
      context.read<KeystoreProvider>();

  void _refresh(BuildContext context) {
    setState(() {
      _hasKeystoreFuture = _provider(context).hasKeystore();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh(context);
    });
  }

  Future<Map<String, dynamic>?> _askAliasAndPassword({
    required String title,
    String? defaultAlias,
    String? defaultPassword,
  }) {
    return showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => GeneratedFormModal(
        title: title,
        items: [
          [
            GeneratedFormTextField(
              'alias',
              label: tr('alias'),
              value: defaultAlias ?? '',
            ),
          ],
          [
            GeneratedFormTextField(
              'password',
              label: tr('password'),
              password: true,
              value: defaultPassword ?? '',
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _generate() async {
    final provider = _provider(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('generateKeystore')),
        content: Text(tr('generateKeystoreWarning')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('generate')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final values = await _askAliasAndPassword(
      title: tr('generateKeystore'),
      defaultAlias: provider.alias,
      defaultPassword: provider.password,
    );
    if (values == null) return;
    setState(() => _busy = true);
    try {
      await provider.regenerate(
        alias: values['alias']?.toString(),
        password: values['password']?.toString(),
      );
      if (!mounted) return;
      showMessage(tr('keystoreGenerated'), context);
      _refresh(context);
    } catch (e) {
      if (mounted) showError(e, context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    final values = await _askAliasAndPassword(title: tr('importKeystore'));
    if (values == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await File(path).readAsBytes();
      final provider = _provider(context);
      final ok = await provider.importFromBytes(
        Uint8List.fromList(bytes),
        alias: values['alias']?.toString() ?? '',
        password: values['password']?.toString() ?? '',
      );
      if (!mounted) return;
      if (ok) {
        showMessage(tr('keystoreImported'), context);
        _refresh(context);
      } else {
        showMessage(tr('keystoreImportWrongCredentials'), context, isError: true);
      }
    } catch (e) {
      if (mounted) showError(e, context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final settingsProvider = context.read<SettingsProvider>();
    setState(() => _busy = true);
    try {
      final provider = _provider(context);
      final bytes = await provider.exportToBytes();
      if (bytes == null) {
        if (mounted) {
          showMessage(tr('noKeystoreToExport'), context, isError: true);
        }
        return;
      }
      var exportDir = await settingsProvider.getExportDir();
      if (exportDir == null) {
        await settingsProvider.pickExportDir();
        exportDir = await settingsProvider.getExportDir();
      }
      if (exportDir == null) return;
      final result = await saf.createFile(
        exportDir,
        displayName:
            'obtainium-keystore-${DateTime.now().toIso8601String().replaceAll(':', '-')}.keystore',
        mimeType: 'application/octet-stream',
        bytes: Uint8List.fromList(bytes),
      );
      if (result == null) {
        throw ObtainiumError(tr('unexpectedError'));
      }
      if (!mounted) return;
      showMessage(
        tr(
          'exportedTo',
          args: [exportDir.pathSegments.join('/').replaceFirst('tree/primary:', '/')],
        ),
        context,
      );
    } catch (e) {
      if (mounted) showError(e, context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasKeystoreFuture,
      builder: (context, snapshot) {
        final hasKeystore = snapshot.data ?? false;
        return ConnectedCard(
          isFirst: true,
          isLast: true,
          padding: null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ActionListTile(
                icon: Icons.vpn_key_outlined,
                label: tr('generateKeystore'),
                trailing: hasKeystore
                    ? Icon(
                        Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: _busy ? null : _generate,
              ),
              ActionListTile(
                icon: Icons.upload_file_outlined,
                label: tr('importKeystore'),
                onTap: _busy ? null : _import,
              ),
              ActionListTile(
                icon: Icons.download_outlined,
                label: tr('exportKeystore'),
                onTap: _busy || !hasKeystore ? null : _export,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  tr('keystoreExplanation'),
                  style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
