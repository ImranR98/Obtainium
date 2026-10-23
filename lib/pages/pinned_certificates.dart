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
              CustomAppBar(
                title: tr('certificatePinning'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.help_outline),
                    tooltip: tr('about'),
                    onPressed: () => showCertificatePinningHelp(context),
                  ),
                ],
              ),
              SliverPadding(
                padding: AppPaddings.page,
                sliver: SliverToBoxAdapter(
                  child: TvInitialFocus(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _pinningGroup(
                          context,
                          settingsProvider,
                          pinning,
                          anyPins,
                        ),
                        if (store.loadError != null) ...[
                          const SizedBox(height: AppSpacings.md),
                          CardTile(
                            padding: EdgeInsets.zero,
                            child: ListTile(
                              contentPadding: AppPaddings.rowHorizontal,
                              leading: Icon(
                                Icons.error_outline,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              title: Text(tr('pinStoreLoadFailed')),
                              subtitle: Text(store.loadError.toString()),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacings.sectionGap),
                        _sectionHeader(tr('yourPinSets')),
                        const SizedBox(height: AppSpacings.sm),
                        _userSetsSection(context, settingsProvider, userSets),
                        const SizedBox(height: AppSpacings.sectionGap),
                        _sectionHeader(tr('builtInPinSets')),
                        const SizedBox(height: AppSpacings.xs),
                        Text(
                          tr('builtInPinSetsDescription'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: AppSpacings.md),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: AppSpacings.md,
                          children: [
                            for (final builtIn in builtInPinnedHosts)
                              _BuiltInPinCard(
                                key: ValueKey(
                                  'builtin-${builtIn.host}-${store.revision}',
                                ),
                                host: builtIn,
                                pinningEnabled: pinning,
                              ),
                          ],
                        ),
                        if (store.hasBuiltInOverrides) ...[
                          const SizedBox(height: AppSpacings.sm),
                          _restoreAllCard(context),
                        ],
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

  Widget _pinningGroup(
    BuildContext context,
    SettingsProvider settingsProvider,
    bool pinning,
    bool anyPins,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacings.connectedGap,
      children: [
        ConnectedCard(
          isFirst: true,
          isLast: false,
          child: ToggleTile(
            label: tr('enableCertificatePinning'),
            value: pinning,
            onChanged: hapticSwitchOnChanged(
              context,
              (value) => settingsProvider.enableCertificatePinning = value,
            ),
          ),
        ),
        ConnectedCard(
          isFirst: false,
          isLast: true,
          child: ListTile(
            contentPadding: AppPaddings.rowHorizontal,
            leading: Icon(
              pinning ? Icons.lock_outline : Icons.lock_open,
              color: colorScheme.primary,
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
      ],
    );
  }

  Widget _userSetsSection(
    BuildContext context,
    SettingsProvider settingsProvider,
    List<UserPinSet> userSets,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacings.md,
      children: [
        if (userSets.isEmpty)
          CardTile(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: AppPaddings.rowHorizontal,
              title: Text(tr('noUserPinSets')),
              subtitle: Text(tr('noUserPinSetsDescription')),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacings.md,
            children: [
              for (final set in userSets)
                _userSetCard(context, settingsProvider, set),
            ],
          ),
        CardTile(
          padding: EdgeInsets.zero,
          child: TvFocusRing(
            borderRadius: AppRadii.small,
            child: ListTile(
              contentPadding: AppPaddings.rowHorizontal,
              leading: Icon(Icons.add, color: colorScheme.primary),
              title: Text(tr('addPinSet')),
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(AppRadii.small),
              ),
              onTap: () {
                settingsProvider.selectionClick();
                _openEditor(context, null);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _userSetCard(
    BuildContext context,
    SettingsProvider settingsProvider,
    UserPinSet set,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final hostLabels = set.hosts.map((host) => host.display).join(', ');
    final hasLabel = set.label.trim().isNotEmpty;
    final subtitle = [
      if (hasLabel) hostLabels,
      plural('certificateHash', set.certificates.length).toLowerCase(),
    ].join(' · ');
    return CardTile(
      padding: EdgeInsets.zero,
      child: TvFocusRing(
        borderRadius: AppRadii.small,
        child: ListTile(
          contentPadding: AppPaddings.rowHorizontal,
          leading: Icon(Icons.lock_outline, color: colorScheme.primary),
          title: Text(hasLabel ? set.displayLabel : hostLabels),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          onTap: () {
            settingsProvider.selectionClick();
            _openEditor(context, set);
          },
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) =>
      SectionHeader(label, padding: EdgeInsets.zero);

  Widget _restoreAllCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CardTile(
      padding: EdgeInsets.zero,
      child: TvFocusRing(
        borderRadius: AppRadii.small,
        child: ListTile(
          contentPadding: AppPaddings.rowHorizontal,
          leading: Icon(Icons.restore, color: colorScheme.primary),
          title: Text(tr('restoreAllBuiltInPins')),
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          onTap: () => _restoreAllBuiltIn(context),
        ),
      ),
    );
  }

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

Future<void> showCertificatePinningHelp(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('certificatePinning')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacings.md,
          children: [
            Text(tr('certificatePinningExclusiveHelp')),
            Text(tr('certificatePinningAdditiveHelp')),
            Text(tr('certificatePinningRedirectHelp')),
            Text(tr('pinSetBuiltInOverrideHelp')),
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: ctx.read<SettingsProvider>().isTV,
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(tr('ok')),
        ),
      ],
    ),
  );
}

class _BuiltInPinCard extends StatelessWidget {
  final BuiltInPinnedHost host;
  final bool pinningEnabled;

  const _BuiltInPinCard({
    super.key,
    required this.host,
    required this.pinningEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final store = PinStore.instance;
    final enabled = store.builtInHostEnabled(host.host);
    final enabledCerts = store.enabledBuiltInCertificates(host);
    final overrides = store.overlappingUserSets(host.host);
    final overridden = overrides.isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;
    final rows = <Widget>[
      ListTile(
        contentPadding: AppPaddings.rowHorizontal,
        title: Text(
          host.host,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          host.includeSubdomains
              ? tr('hostAndSubdomains', args: [host.host])
              : tr('hostOnly', args: [host.host]),
        ),
        trailing: IconButton(
          tooltip: enabled ? tr('removeBuiltInPin') : tr('restoreBuiltInPin'),
          icon: Icon(enabled ? Icons.delete_outline : Icons.restore),
          onPressed: () =>
              enabled ? _removeHost(context) : _restoreHost(context),
        ),
      ),
    ];

    if (!enabled) {
      rows.add(
        ListTile(
          contentPadding: AppPaddings.rowHorizontal,
          leading: Icon(
            Icons.info_outline,
            color: colorScheme.onSurfaceVariant,
          ),
          title: Text(tr('builtInPinRemoved')),
          subtitle: Text(tr('builtInPinRemovedDescription')),
        ),
      );
    } else {
      if (overridden) {
        rows.add(
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
        );
      }
      for (final certificate in host.certificates) {
        rows.add(
          _BuiltInCertificateTile(
            host: host,
            certificate: certificate,
            enabled: store.builtInCertEnabled(host.host, certificate),
            lastEnabled:
                enabledCerts.length == 1 &&
                enabledCerts.first.sha256 == certificate.sha256,
          ),
        );
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacings.lg,
            AppSpacings.md,
            AppSpacings.lg,
            AppSpacings.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                pinningEnabled
                    ? Icons.verified_user_outlined
                    : Icons.lock_open_outlined,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacings.sm),
              Expanded(
                child: Text(
                  pinningEnabled
                      ? tr('builtInPinActive')
                      : tr('pinningCurrentlyDisabled'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacings.connectedGap,
      children: [
        for (var i = 0; i < rows.length; i++)
          ConnectedCard(
            isFirst: i == 0,
            isLast: i == rows.length - 1,
            child: rows[i],
          ),
      ],
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
