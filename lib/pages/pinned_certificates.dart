import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/providers/document_tree_bridge.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/services/pinned_certificates.dart';
import 'package:obtainium/theme.dart';
import 'package:obtainium/utils/nav_helper.dart';
import 'package:provider/provider.dart';

class PinnedCertificatesView extends StatelessWidget {
  const PinnedCertificatesView({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacings.sectionGap,
      children: [
        CardTile(
          child: ListTile(
            leading: Icon(
              settingsProvider.enableCertificatePinning
                  ? Icons.lock_outline
                  : Icons.lock_open,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              tr(
                settingsProvider.enableCertificatePinning
                    ? 'pinningCurrentlyEnabled'
                    : 'pinningCurrentlyDisabled',
              ),
            ),
            subtitle: Text(tr('pinnedCertificatesDescription')),
          ),
        ),
        for (final pinnedHost in pinnedHosts) ...[
          SectionHeader(pinnedHost.host),
          ...shapeCardTiles([
            for (final certificate in pinnedHost.certificates)
              CardTile(
                padding: EdgeInsets.zero,
                child: TvFocusRing(
                  borderRadius: AppRadii.small,
                  child: ListTile(
                    contentPadding: AppPaddings.rowHorizontal,
                    title: Text(certificate.displayName),
                    subtitle: Text(certificate.subject),
                    trailing: const Icon(Icons.chevron_right),
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(AppRadii.small),
                    ),
                    onTap: () {
                      context.read<SettingsProvider>().selectionClick();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          traversalEdgeBehavior: traversalEdgeBehaviorFor(
                            context,
                          ),
                          builder: (_) => PinnedCertificateDetailPage(
                            host: pinnedHost.host,
                            certificate: certificate,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ]),
        ],
      ],
    );
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
        message: 'Failed to export pinned certificate ${certificate.assetPath}',
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
