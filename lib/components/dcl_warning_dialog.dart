import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:obtainium/theme.dart';

class DclWarningDialog extends StatelessWidget {
  const DclWarningDialog({
    super.key,
    required this.onOpenSettings,
    this.autofocus = false,
  });

  final VoidCallback onOpenSettings;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('androidCertStoreWarningTitle')),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpacings.sectionGap,
        children: [
          Text(tr('androidCertStoreWarningP1')),
          Text(tr('androidCertStoreWarningP2')),
          Text(tr('androidCertStoreWarningP3')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('ok')),
        ),
        FilledButton.tonal(
          autofocus: autofocus,
          onPressed: () {
            Navigator.of(context).pop();
            onOpenSettings();
          },
          child: Text(tr('openAppSettings')),
        ),
      ],
    );
  }
}
