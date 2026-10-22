import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/components/generated_form_renderer.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/pages/pinned_certificates.dart';
import 'package:obtainium/providers/certificate_bridge.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/services/pin_store.dart';
import 'package:obtainium/services/pinned_certificates.dart';
import 'package:obtainium/theme.dart';
import 'package:obtainium/utils/nav_helper.dart';
import 'package:provider/provider.dart';

class PinSetEditorPage extends StatefulWidget {
  final UserPinSet? existing;

  const PinSetEditorPage({super.key, this.existing});

  @override
  State<PinSetEditorPage> createState() => _PinSetEditorPageState();
}

class _PinSetEditorPageState extends State<PinSetEditorPage> {
  static const int _maxFileBytes = 2 * 1024 * 1024;
  static const int _maxCertificates = 50;

  late final TextEditingController _labelController;
  late final FocusNode _labelFocusNode;
  late final List<_HostDraft> _hosts;
  late final List<PinnedCertificate> _certificates;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(
      text: widget.existing?.label ?? '',
    );
    _labelFocusNode = FocusNode();
    _hosts = widget.existing == null || widget.existing!.hosts.isEmpty
        ? [_HostDraft()]
        : [
            for (final host in widget.existing!.hosts)
              _HostDraft(
                host: host.host,
                includeSubdomains: host.includeSubdomains,
              ),
          ];
    _certificates = [...?widget.existing?.certificates];
  }

  @override
  void dispose() {
    _labelController.dispose();
    _labelFocusNode.dispose();
    for (final host in _hosts) {
      host.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          CustomAppBar(
            title: widget.existing == null ? tr('addPinSet') : tr('editPinSet'),
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
                    _introCard(context),
                    const SizedBox(height: AppSpacings.lg),
                    ConnectedCard(
                      color: colorScheme.surfaceContainerHighest,
                      child: _tvTextFieldFocus(
                        context,
                        _labelFocusNode,
                        TextField(
                          controller: _labelController,
                          focusNode: _labelFocusNode,
                          decoration: InputDecoration(
                            labelText: tr('pinSetName'),
                            hintText: tr('pinSetNameHint'),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacings.xl),
                    _sectionHeader(tr('pinSetHosts')),
                    const SizedBox(height: AppSpacings.sm),
                    _hostInputs(context),
                    const SizedBox(height: AppSpacings.xl),
                    _sectionHeader(tr('pinSetCertificates')),
                    const SizedBox(height: AppSpacings.sm),
                    if (_certificates.isEmpty)
                      _emptyCertificatesCard(context)
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: AppSpacings.connectedGap,
                        children: shapeCardTiles([
                          for (var i = 0; i < _certificates.length; i++)
                            _certificateCard(context, i),
                        ]),
                      ),
                    const SizedBox(height: AppSpacings.md),
                    _certificateActions(context),
                    const SizedBox(height: AppSpacings.md),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(tr('save')),
                    ),
                    if (widget.existing != null) ...[
                      const SizedBox(height: AppSpacings.md),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _delete,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(tr('deletePinSet')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.error,
                        ),
                      ),
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
      ),
    );
  }

  Widget _introCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CardTile(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: AppPaddings.rowHorizontal,
        leading: Icon(Icons.lock_outline, color: colorScheme.primary),
        title: Text(tr('pinSetIntroTitle')),
        subtitle: Text(tr('pinSetIntroDescription')),
      ),
    );
  }

  Widget _sectionHeader(String label) =>
      SectionHeader(label, padding: EdgeInsets.zero);

  Widget _emptyCertificatesCard(BuildContext context) => CardTile(
    padding: EdgeInsets.zero,
    child: ListTile(
      contentPadding: AppPaddings.rowHorizontal,
      leading: Icon(
        Icons.verified_user_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(tr('noPinnedCertificates')),
      subtitle: Text(tr('noPinnedCertificatesDescription')),
    ),
  );

  Widget _certificateActions(BuildContext context) => Row(
    spacing: AppSpacings.md,
    children: [
      Expanded(
        child: FilledButton.tonalIcon(
          onPressed: _pickCertificates,
          icon: const Icon(Icons.upload_file),
          label: Text(tr('uploadCertificate')),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacings.md),
          ),
        ),
      ),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: _pasteCertificate,
          icon: const Icon(Icons.content_paste),
          label: Text(tr('pastePem')),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacings.md),
          ),
        ),
      ),
    ],
  );

  Widget _tvTextFieldFocus(
    BuildContext context,
    FocusNode focusNode,
    Widget child,
  ) {
    if (!context.read<SettingsProvider>().isTV) return child;
    return TvTextFieldFocus(textFocusNode: focusNode, child: child);
  }

  Widget _hostInputs(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacings.md,
      children: [
        for (var i = 0; i < _hosts.length; i++)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacings.connectedGap,
            children: [
              ConnectedCard(
                isFirst: true,
                isLast: false,
                color: colorScheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    Expanded(
                      child: _tvTextFieldFocus(
                        context,
                        _hosts[i].focusNode,
                        TextField(
                          controller: _hosts[i].controller,
                          focusNode: _hosts[i].focusNode,
                          decoration: InputDecoration(
                            labelText: tr('host'),
                            hintText: tr('hostHint'),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('remove'),
                      onPressed: () => _removeHost(i),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
              ConnectedCard(
                isFirst: false,
                isLast: true,
                color: colorScheme.surfaceContainerLow,
                child: ToggleTile(
                  label: tr('includeSubdomains'),
                  subtitle: Text(tr('includeSubdomainsHelp')),
                  value: _hosts[i].includeSubdomains,
                  onChanged: hapticSwitchOnChanged(
                    context,
                    (value) =>
                        setState(() => _hosts[i].includeSubdomains = value),
                  ),
                ),
              ),
            ],
          ),
        CardTile(
          padding: EdgeInsets.zero,
          child: TvFocusRing(
            borderRadius: AppRadii.small,
            child: ListTile(
              contentPadding: AppPaddings.rowHorizontal,
              leading: Icon(Icons.add, color: colorScheme.primary),
              title: Text(tr('addHost')),
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(AppRadii.small),
              ),
              onTap: _addHost,
            ),
          ),
        ),
      ],
    );
  }

  Widget _certificateCard(BuildContext context, int index) {
    final certificate = _certificates[index];
    return CardTile(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: AppPaddings.rowHorizontal,
        title: Text(certificate.displayName),
        subtitle: Text(
          certificate.subject,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: tr('remove'),
          icon: const Icon(Icons.delete_outline),
          onPressed: () => setState(() => _certificates.removeAt(index)),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            traversalEdgeBehavior: traversalEdgeBehaviorFor(context),
            builder: (_) => PinnedCertificateDetailPage(
              host: _hosts
                  .map((host) => normalizePinHost(host.controller.text))
                  .whereType<String>()
                  .join(', '),
              certificate: certificate,
            ),
          ),
        ),
      ),
    );
  }

  void _addHost() {
    setState(() => _hosts.add(_HostDraft()));
  }

  void _removeHost(int index) {
    final removed = _hosts.removeAt(index);
    removed.dispose();
    if (_hosts.isEmpty) _hosts.add(_HostDraft());
    setState(() {});
  }

  Future<void> _pickCertificates() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: tr('uploadCertificate'),
      type: FileType.custom,
      allowedExtensions: const ['pem', 'crt', 'cer', 'der'],
    );
    if (files.isEmpty) return;
    final errors = <String>[];
    var added = 0;
    for (final file in files) {
      try {
        final length = await file.length();
        if (length != null && length > _maxFileBytes) {
          errors.add(tr('certificateFileTooLarge', args: [file.name]));
          continue;
        }
        final bytes = await file.readAsBytes();
        var ders = <Uint8List>[];
        try {
          ders = pemBlocksToDers(utf8.decode(bytes, allowMalformed: true));
        } on FormatException {
          ders = [];
        }
        if (ders.isEmpty) ders = [bytes];
        added += await _addDers(ders);
      } catch (e) {
        errors.add('${file.name}: $e');
      }
    }
    if (!mounted) return;
    setState(() {});
    if (errors.isNotEmpty) {
      showError(ObtainiumError(errors.join('\n')), context);
    } else if (added == 0) {
      showMessage(tr('noNewCertificates'), context);
    }
  }

  Future<void> _pasteCertificate() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('pastePem')),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 6,
          maxLines: 12,
          decoration: InputDecoration(hintText: tr('pastePemHint')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(tr('add')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) return;
    var ders = <Uint8List>[];
    try {
      ders = pemBlocksToDers(text);
    } on FormatException {
      ders = [];
    }
    if (ders.isEmpty) {
      showError(ObtainiumError(tr('invalidCertificate')), context);
      return;
    }
    try {
      final added = await _addDers(ders);
      if (!mounted) return;
      setState(() {});
      if (added == 0) showMessage(tr('noNewCertificates'), context);
    } catch (e) {
      if (mounted) showError(e, context);
    }
  }

  Future<int> _addDers(List<Uint8List> ders) async {
    final infos = await CertificateBridge.instance.parse(ders);
    var added = 0;
    for (final info in infos) {
      if (_certificates.length >= _maxCertificates) {
        throw ObtainiumError(tr('tooManyCertificates'));
      }
      final sha256 = certificateFingerprint(info.der);
      if (_certificates.any((cert) => cert.sha256 == sha256)) continue;
      _certificates.add(
        PinnedCertificate(
          pem: derToPem(info.der),
          displayName: info.displayName,
          subject: info.subject,
          issuer: info.issuer,
          notBefore: info.notBefore,
          notAfter: info.notAfter,
          sha256: sha256,
        ),
      );
      added++;
    }
    return added;
  }

  Future<void> _save() async {
    final hosts = <PinHostRule>[];
    for (final draft in _hosts) {
      final raw = draft.controller.text.trim();
      if (raw.isEmpty) continue;
      final normalized = normalizePinHost(raw);
      if (normalized == null) {
        showError(ObtainiumError(tr('invalidHost')), context);
        return;
      }
      final rule = PinHostRule(
        host: normalized,
        includeSubdomains: draft.includeSubdomains || raw.startsWith('*.'),
      );
      if (hosts.any(
        (existing) =>
            existing.host == rule.host &&
            existing.includeSubdomains == rule.includeSubdomains,
      )) {
        showError(
          ObtainiumError(tr('duplicateHost', args: [rule.host])),
          context,
        );
        return;
      }
      hosts.add(rule);
    }
    if (hosts.isEmpty) {
      showError(ObtainiumError(tr('pinSetNeedsHost')), context);
      return;
    }
    if (_certificates.isEmpty) {
      showError(ObtainiumError(tr('pinSetNeedsCertificate')), context);
      return;
    }
    final set = UserPinSet(
      id: widget.existing?.id ?? UserPinSet.newId(),
      label: _labelController.text.trim(),
      hosts: hosts,
      certificates: _certificates,
    );
    try {
      await PinStore.instance.ensureLoaded();
      if (!mounted) return;
      PinStore.instance.validateUserSet(set, ignoreId: widget.existing?.id);
    } on ArgumentError catch (e) {
      showError(ObtainiumError(e.message.toString()), context);
      return;
    }

    final builtInOverlaps = <String>{};
    for (final rule in hosts) {
      for (final builtIn in builtInPinnedHosts) {
        final builtInRule = PinHostRule(
          host: builtIn.host,
          includeSubdomains: builtIn.includeSubdomains,
        );
        if (rule.matches(builtIn.host) || builtInRule.matches(rule.host)) {
          builtInOverlaps.add(builtIn.host);
        }
      }
    }
    if (builtInOverlaps.isNotEmpty) {
      final proceed = await showConfirmDialog(
        context,
        title: tr('pinSetOverridesBuiltInTitle'),
        content: Text(
          tr(
            'pinSetOverridesBuiltInConfirmation',
            args: [builtInOverlaps.join(', ')],
          ),
        ),
        confirmText: tr('save'),
      );
      if (!proceed || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      if (widget.existing == null) {
        await PinStore.instance.addUserSet(set);
      } else {
        await PinStore.instance.updateUserSet(set);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(e, context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: tr('deletePinSet'),
      content: Text(
        tr('deletePinSetConfirmation', args: [existing.displayLabel]),
      ),
      confirmText: tr('delete'),
    );
    if (!confirmed) return;
    try {
      await PinStore.instance.deleteUserSet(existing.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(e, context);
    }
  }
}

class _HostDraft {
  final TextEditingController controller;
  final FocusNode focusNode;
  bool includeSubdomains;

  _HostDraft({String host = '', this.includeSubdomains = false})
    : controller = TextEditingController(text: host),
      focusNode = FocusNode();

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}
