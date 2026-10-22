import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/pages/pin_set_editor.dart';
import 'package:obtainium/providers/document_tree_bridge.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/services/pin_store.dart';
import 'package:obtainium/services/pinned_certificates.dart';
import 'package:obtainium/theme.dart';
import 'package:obtainium/utils/nav_helper.dart';
import 'package:provider/provider.dart';

class CertificatePinningPage extends StatefulWidget {
  const CertificatePinningPage({super.key});

  @override
  State<CertificatePinningPage> createState() => _CertificatePinningPageState();
}

class _CertificatePinningPageState extends State<CertificatePinningPage> {
  @override
  void initState() {
    super.initState();
    PinStore.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: ListenableBuilder(
        listenable: PinStore.instance,
        builder: (context, _) {
          final settingsProvider = context.watch<SettingsProvider>();
          final store = PinStore.instance;
          final pinning = settingsProvider.enableCertificatePinning;
          final userSets = store.userSets;
          final anyPins =
              userSets.isNotEmpty ||
              builtInPinnedHosts.any(
                (host) =>
                    store.builtInHostEnabled(host.host) &&
                    store.enabledBuiltInCertificates(host).isNotEmpty,
              );
          return CustomScrollView(
            slivers: [
              CustomAppBar(title: tr('certificatePinning')),
              SliverPadding(
                padding: AppPaddings.page,
                sliver: SliverToBoxAdapter(
                  child: TvInitialFocus(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: AppSpacings.sectionGap,
                      children: [
                        _explanationCard(context),
                        ToggleTile(
                          label: tr('enableCertificatePinning'),
                          value: pinning,
                          onChanged: (value) =>
                              settingsProvider.enableCertificatePinning = value,
                          helpWidgets: [
                            Text(tr('certificatePinningExclusiveHelp')),
                            const SizedBox(height: AppSpacings.elementGap),
                            Text(tr('certificatePinningAdditiveHelp')),
                          ],
                        ),
                        CardTile(
                          child: ListTile(
                            leading: Icon(
                              pinning ? Icons.lock_outline : Icons.lock_open,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            title: Text(
                              tr(
                                pinning
                                    ? 'pinningCurrentlyEnabled'
                                    : 'pinningCurrentlyDisabled',
                              ),
                            ),
                            subtitle: Text(
                              tr(
                                pinning
                                    ? (anyPins
                                          ? 'pinningAppliesToConfiguredHosts'
                                          : 'pinningEnabledNoHosts')
                                    : 'pinningDisabledUsesAndroidStore',
                              ),
                            ),
                          ),
                        ),
                        if (store.loadError != null)
                          CardTile(
                            child: ListTile(
                              leading: Icon(
                                Icons.error_outline,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              title: Text(tr('pinStoreLoadFailed')),
                              subtitle: Text(store.loadError.toString()),
                            ),
                          ),
                        SectionHeader(tr('yourPinSets')),
                        if (userSets.isEmpty)
                          CardTile(
                            child: ListTile(
                              title: Text(tr('noUserPinSets')),
                              subtitle: Text(tr('noUserPinSetsDescription')),
                            ),
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: AppSpacings.connectedGap,
                            children: shapeCardTiles([
                              for (final set in userSets)
                                CardTile(
                                  padding: EdgeInsets.zero,
                                  child: TvFocusRing(
                                    borderRadius: AppRadii.small,
                                    child: ListTile(
                                      contentPadding: AppPaddings.rowHorizontal,
                                      title: Text(set.displayLabel),
                                      subtitle: Text(
                                        [
                                          set.hosts
                                              .map((host) => host.display)
                                              .join(', '),
                                          plural(
                                            'certificateHash',
                                            set.certificates.length,
                                          ).toLowerCase(),
                                        ].join(' · '),
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      shape: RoundedSuperellipseBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppRadii.small,
                                        ),
                                      ),
                                      onTap: () {
                                        settingsProvider.selectionClick();
                                        _openEditor(context, set);
                                      },
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                        CardTile(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: () => _openEditor(context, null),
                              icon: const Icon(Icons.add),
                              label: Text(tr('addPinSet')),
                            ),
                          ),
                        ),
                        SectionHeader(tr('builtInPinSets')),
                        CardTile(
                          child: ListTile(
                            title: Text(tr('builtInPinSetsDescription')),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: AppSpacings.connectedGap,
                          children: [
                            for (var i = 0; i < builtInPinnedHosts.length; i++)
                              _BuiltInPinCard(
                                key: ValueKey(
                                  'builtin-${builtInPinnedHosts[i].host}-${store.revision}',
                                ),
                                host: builtInPinnedHosts[i],
                                pinningEnabled: pinning,
                                isFirst: i == 0,
                                isLast: i == builtInPinnedHosts.length - 1,
                              ),
                          ],
                        ),
                        if (store.hasBuiltInOverrides)
                          CardTile(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _restoreAllBuiltIn(context),
                                icon: const Icon(Icons.restore),
                                label: Text(tr('restoreAllBuiltInPins')),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: MediaQuery.of(context).padding.bottom),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _explanationCard(BuildContext context) => CardTile(
    padding: const EdgeInsets.all(AppSpacings.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacings.md,
      children: [
        Text(
          tr('certificatePinning'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(tr('certificatePinningExclusiveHelp')),
        Text(tr('certificatePinningAdditiveHelp')),
        Text(tr('certificatePinningRedirectHelp')),
      ],
    ),
  );

  Future<void> _openEditor(BuildContext context, UserPinSet? set) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        traversalEdgeBehavior: traversalEdgeBehaviorFor(context),
        builder: (_) => PinSetEditorPage(existing: set),
      ),
    );
  }

  Future<void> _restoreAllBuiltIn(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: tr('restoreAllBuiltInPins'),
      content: Text(tr('restoreAllBuiltInPinsConfirmation')),
      confirmText: tr('restore'),
    );
    if (!confirmed) return;
    try {
      await PinStore.instance.restoreAllBuiltIn();
    } catch (e) {
      if (context.mounted) showError(e, context);
    }
  }
}

class _BuiltInPinCard extends StatelessWidget {
  final BuiltInPinnedHost host;
  final bool pinningEnabled;
  final bool isFirst;
  final bool isLast;

  const _BuiltInPinCard({
    super.key,
    required this.host,
    required this.pinningEnabled,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final store = PinStore.instance;
    final enabled = store.builtInHostEnabled(host.host);
    final enabledCerts = store.enabledBuiltInCertificates(host);
    final overrides = store.overlappingUserSets(host.host);
    final overridden = overrides.isNotEmpty;
    return ConnectedCard(
      isFirst: isFirst,
      isLast: isLast,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: AppPaddings.rowHorizontal,
            title: Row(
              children: [
                Flexible(child: Text(host.host)),
                const SizedBox(width: AppSpacings.sm),
                Chip(
                  label: Text(tr('builtIn')),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            subtitle: Text(
              host.includeSubdomains
                  ? tr('hostAndSubdomains', args: [host.host])
                  : tr('hostOnly', args: [host.host]),
            ),
            trailing: IconButton(
              tooltip: enabled
                  ? tr('removeBuiltInPin')
                  : tr('restoreBuiltInPin'),
              icon: Icon(enabled ? Icons.delete_outline : Icons.restore),
              onPressed: () =>
                  enabled ? _removeHost(context) : _restoreHost(context),
            ),
          ),
          if (!enabled)
            ListTile(
              contentPadding: AppPaddings.rowHorizontal,
              leading: Icon(
                Icons.info_outline,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              title: Text(tr('builtInPinRemoved')),
              subtitle: Text(tr('builtInPinRemovedDescription')),
            )
          else ...[
            if (overridden)
              ListTile(
                contentPadding: AppPaddings.rowHorizontal,
                leading: const Icon(Icons.priority_high),
                title: Text(
                  tr(
                    'builtInPinOverridden',
                    args: [overrides.map((set) => set.displayLabel).join(', ')],
                  ),
                ),
                subtitle: Text(tr('builtInPinOverriddenDescription')),
              ),
            for (final certificate in host.certificates)
              _BuiltInCertificateTile(
                host: host,
                certificate: certificate,
                enabled: store.builtInCertEnabled(host.host, certificate),
                lastEnabled:
                    enabledCerts.length == 1 &&
                    enabledCerts.first.sha256 == certificate.sha256,
              ),
          ],
          Padding(
            padding: AppPaddings.rowHorizontal,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    enabled
                        ? (pinningEnabled
                              ? tr('builtInPinActive')
                              : tr('pinningCurrentlyDisabled'))
                        : tr('builtInPinInactive'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacings.sm),
        ],
      ),
    );
  }

  Future<void> _removeHost(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: tr('removeBuiltInPin'),
      content: Text(tr('removeBuiltInPinConfirmation', args: [host.host])),
      confirmText: tr('remove'),
    );
    if (!confirmed) return;
    try {
      await PinStore.instance.setBuiltInHostEnabled(host.host, false);
    } catch (e) {
      if (context.mounted) showError(e, context);
    }
  }

  Future<void> _restoreHost(BuildContext context) async {
    try {
      await PinStore.instance.restoreBuiltInHost(host.host);
    } catch (e) {
      if (context.mounted) showError(e, context);
    }
  }
}

class _BuiltInCertificateTile extends StatelessWidget {
  final BuiltInPinnedHost host;
  final PinnedCertificate certificate;
  final bool enabled;
  final bool lastEnabled;

  const _BuiltInCertificateTile({
    required this.host,
    required this.certificate,
    required this.enabled,
    required this.lastEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: AppPaddings.rowHorizontal,
      title: Text(certificate.displayName),
      subtitle: Text(
        certificate.subject,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: enabled
            ? tr('removeBuiltInCertificate')
            : tr('restoreBuiltInCertificate'),
        icon: Icon(enabled ? Icons.delete_outline : Icons.restore),
        onPressed: () => enabled
            ? _removeCertificate(context)
            : _restoreCertificate(context),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          traversalEdgeBehavior: traversalEdgeBehaviorFor(context),
          builder: (_) => PinnedCertificateDetailPage(
            host: host.host,
            certificate: certificate,
          ),
        ),
      ),
    );
  }

  Future<void> _removeCertificate(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: tr('removeBuiltInCertificate'),
      content: Text(
        tr(
          lastEnabled
              ? 'removeLastBuiltInCertificateConfirmation'
              : 'removeBuiltInCertificateConfirmation',
          args: [certificate.displayName, host.host],
        ),
      ),
      confirmText: tr('remove'),
    );
    if (!confirmed) return;
    try {
      if (lastEnabled) {
        await PinStore.instance.setBuiltInHostEnabled(host.host, false);
      } else {
        await PinStore.instance.setBuiltInCertEnabled(
          host.host,
          certificate.sha256,
          false,
        );
      }
    } catch (e) {
      if (context.mounted) showError(e, context);
    }
  }

  Future<void> _restoreCertificate(BuildContext context) async {
    try {
      await PinStore.instance.setBuiltInCertEnabled(
        host.host,
        certificate.sha256,
        true,
      );
    } catch (e) {
      if (context.mounted) showError(e, context);
    }
  }
}

class PinnedCertificateDetailPage extends StatelessWidget {
  final String host;
  final PinnedCertificate certificate;

  const PinnedCertificateDetailPage({
    super.key,
    required this.host,
    required this.certificate,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          CustomAppBar(title: certificate.displayName),
          SliverPadding(
            padding: AppPaddings.page,
            sliver: SliverToBoxAdapter(
              child: TvInitialFocus(
                child: FutureBuilder<PinnedCertificateContents>(
                  future: loadPinnedCertificateContents(certificate),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return CardTile(
                        child: ListTile(
                          title: Text(tr('error')),
                          subtitle: Text(snapshot.error.toString()),
                        ),
                      );
                    }
                    final contents = snapshot.data;
                    if (contents == null) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacings.xl),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: AppSpacings.sectionGap,
                      children: [
                        _CertificateInfoCard(
                          host: host,
                          certificate: certificate,
                          contents: contents,
                        ),
                        _CertificatePemCard(pem: contents.pem),
                        Row(
                          spacing: AppSpacings.md,
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: () =>
                                    copyToClipboard(context, contents.pem),
                                icon: const Icon(Icons.copy),
                                label: Text(tr('copyToClipboard')),
                              ),
                            ),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _exportCertificate(
                                  context,
                                  certificate,
                                  contents.pem,
                                ),
                                icon: const Icon(Icons.save_alt),
                                label: Text(tr('exportCertificate')),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.bottom),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCertificate(
    BuildContext context,
    PinnedCertificate certificate,
    String pem,
  ) async {
    final bytes = Uint8List.fromList(utf8.encode(pem));
    if (context.read<SettingsProvider>().isTV) {
      await _exportToDownloads(context, certificate, bytes);
      return;
    }
    try {
      final uri = await FilePicker.saveFile(
        fileName: certificate.exportFileName,
        bytes: bytes,
        mimeType: 'application/x-pem-file',
        dialogTitle: tr('exportCertificate'),
      );
      if (!context.mounted || uri == null) return;
      showMessage(tr('certificateExported'), context);
    } catch (e) {
      AppLogger.error(
        e,
        message:
            'Failed to export pinned certificate ${certificate.displayName}',
      );
      await _exportToDownloads(context, certificate, bytes);
    }
  }

  Future<void> _exportToDownloads(
    BuildContext context,
    PinnedCertificate certificate,
    Uint8List bytes,
  ) async {
    try {
      final path = await DocumentTreeBridge.instance.exportToDownloads(
        name: certificate.exportFileName,
        mimeType: 'application/x-pem-file',
        bytes: bytes,
      );
      if (!context.mounted) return;
      if (path != null) {
        showMessage(tr('exportedTo', args: [path]), context);
        return;
      }
    } catch (e) {
      AppLogger.error(
        e,
        message: 'Failed to export pinned certificate to Downloads',
      );
    }
    if (!context.mounted) return;
    showError(ObtainiumError(tr('certificateExportFailed')), context);
  }
}

class _CertificateInfoCard extends StatelessWidget {
  final String host;
  final PinnedCertificate certificate;
  final PinnedCertificateContents contents;

  const _CertificateInfoCard({
    required this.host,
    required this.certificate,
    required this.contents,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.yMMMd().add_Hm();
    return CardTile(
      padding: const EdgeInsets.all(AppSpacings.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacings.md,
        children: [
          _InfoRow(label: tr('host'), value: host),
          _InfoRow(label: tr('certificateSubject'), value: certificate.subject),
          _InfoRow(label: tr('certificateIssuer'), value: certificate.issuer),
          _InfoRow(
            label: tr('certificateValidFrom'),
            value: dateFormat.format(certificate.notBefore.toLocal()),
          ),
          _InfoRow(
            label: tr('certificateValidUntil'),
            value: dateFormat.format(certificate.notAfter.toLocal()),
          ),
          _InfoRow(label: tr('certificateSha256'), value: contents.sha256),
        ],
      ),
    );
  }
}

class _CertificatePemCard extends StatelessWidget {
  final String pem;

  const _CertificatePemCard({required this.pem});

  @override
  Widget build(BuildContext context) {
    return CardTile(
      padding: const EdgeInsets.all(AppSpacings.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacings.md,
        children: [
          Text(
            tr('certificatePem'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SelectableText(
            pem.trim(),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 2,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        SelectableText(value),
      ],
    );
  }
}
