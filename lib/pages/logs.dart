import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/core/logging/app_logger.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/theme.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  static const List<int> _dayOptions = [7, 5, 4, 3, 2, 1];

  final ScrollController _scrollController = ScrollController();
  List<LogEntry> _logs = [];
  int _days = _dayOptions.first;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs(_days);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs(int days) async {
    setState(() => _loading = true);
    final value = await AppLogger.getLogs(
      after: DateTime.now().subtract(Duration(days: days)),
    );
    if (!mounted) return;
    setState(() {
      _days = days;
      _logs = value;
      _loading = false;
    });
  }

  String _joinLogs() => _logs.map((e) => e.toString()).join('\n\n');

  void _scrollTo(double offset) {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      offset,
      duration: ExpressiveMotion.medium,
      curve: ExpressiveMotion.emphasized,
    );
  }

  void _scrollToTop() => _scrollTo(0);

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollTo(_scrollController.position.maxScrollExtent);
  }

  Future<void> _clearLogs() async {
    final cont = await showContinueCancelDialog(
      context,
      title: tr('appLogs'),
      message: tr('removeFromObtainium'),
    );
    if (!cont) return;
    await AppLogger.clearLogs();
    if (!mounted) return;
    await _loadLogs(_days);
  }

  void _shareLogs() {
    unawaited(
      SharePlus.instance.share(
        ShareParams(text: _joinLogs(), subject: tr('appLogs')),
      ),
    );
  }

  Color _levelColor(BuildContext context, AppLogLevel level) {
    final cs = Theme.of(context).colorScheme;
    return switch (level) {
      AppLogLevel.error => cs.error,
      AppLogLevel.warning => cs.tertiary,
      AppLogLevel.debug => cs.onSurfaceVariant,
      AppLogLevel.info => cs.onSurface,
    };
  }

  Widget _logTile(LogEntry log) {
    final color = _levelColor(context, log.level);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${log.timestamp.toString()} · ${log.level.name}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color.withValues(alpha: 0.8),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            log.message,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _toolbarDivider(ColorScheme cs) => Container(
    width: 1,
    height: 24,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: cs.outlineVariant,
  );

  /// A single M3 Expressive floating toolbar that consolidates navigation
  /// (jump to top/bottom) and actions (filter, share, clear) into one pill,
  /// rather than scattering them across the app bar and multiple FABs.
  Widget _buildFloatingToolbar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasLogs = _logs.isNotEmpty;
    return Material(
      elevation: 3,
      color: cs.surfaceContainer,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: hasLogs ? _scrollToTop : null,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            IconButton(
              onPressed: hasLogs ? _scrollToBottom : null,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
            _toolbarDivider(cs),
            PopupMenuButton<int>(
              icon: const Icon(Icons.filter_list_rounded),
              tooltip: tr('filter'),
              initialValue: _days,
              onSelected: _loadLogs,
              itemBuilder: (context) => _dayOptions
                  .map(
                    (e) => CheckedPopupMenuItem<int>(
                      value: e,
                      checked: e == _days,
                      child: Text(plural('day', e)),
                    ),
                  )
                  .toList(),
            ),
            IconButton(
              onPressed: hasLogs
                  ? () {
                      context.read<SettingsProvider>().selectionClick();
                      _shareLogs();
                    }
                  : null,
              icon: const Icon(Icons.share_rounded),
              tooltip: tr('share'),
            ),
            IconButton(
              onPressed: hasLogs
                  ? () {
                      context.read<SettingsProvider>().selectionClick();
                      _clearLogs();
                    }
                  : null,
              color: cs.error,
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: tr('remove'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          SelectionArea(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverAppBar(
                  pinned: true,
                  automaticallyImplyLeading: false,
                  title: Text(tr('appLogs')),
                ),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_logs.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.bug_report_outlined,
                      message: tr('noLogs'),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: _logs.length,
                    itemBuilder: (context, index) => _logTile(_logs[index]),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
          ),
          // Docked in a Stack rather than the Scaffold's floatingActionButton
          // slot so it doesn't play the FAB scale/rotate entrance animation.
          if (!_loading)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: _buildFloatingToolbar(context),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
