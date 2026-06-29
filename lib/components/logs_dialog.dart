import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/generated_form_modal.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

class LogsDialog extends StatefulWidget {
  const LogsDialog({super.key});

  @override
  State<LogsDialog> createState() => _LogsDialogState();
}

class _LogsDialogState extends State<LogsDialog> {
  String? logString;
  List<int> days = [7, 5, 4, 3, 2, 1];

  @override
  void initState() {
    super.initState();
    filterLogs(days.first);
  }

  void filterLogs(int days) {
    context.read<LogsProvider>()
        .get(after: DateTime.now().subtract(Duration(days: days)))
        .then((value) {
      if (!mounted) return;
      setState(() {
        String l = value.map((e) => e.toString()).join('\n\n');
        logString = l.isNotEmpty ? l : tr('noLogs');
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(tr('appLogs')),
      content: Column(
        children: [
          DropdownMenu(
            initialSelection: days.first,
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: days
                .map(
                  (e) => DropdownMenuEntry(value: e, label: plural('day', e)),
                )
                .toList(),
            onSelected: (d) {
              filterLogs(d ?? 7);
            },
          ),
          const SizedBox(height: 32),
          Text(logString ?? ''),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () async {
            final logsProvider = context.read<LogsProvider>();
            var cont =
                (await showDialog<Map<String, dynamic>?>(
                  context: context,
                  builder: (BuildContext ctx) {
                    return GeneratedFormModal(
                      title: tr('appLogs'),
                      items: const [],
                      initValid: true,
                      message: tr('removeFromObtainium'),
                    );
                  },
                )) !=
                null;
            if (cont) {
              logsProvider.clear();
              if (context.mounted) Navigator.of(context).pop();
            }
          },
          child: Text(tr('remove')),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(tr('close')),
        ),
        FilledButton.tonal(
          onPressed: () {
            SharePlus.instance
                .share(
                  ShareParams(text: logString ?? '', subject: tr('appLogs')),
                )
                .ignore();
            Navigator.of(context).pop();
          },
          child: Text(tr('share')),
        ),
      ],
    );
  }
}
