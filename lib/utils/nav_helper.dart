import 'package:material_ui/material_ui.dart';
import 'package:obtainium/pages/add_app.dart';
import 'package:obtainium/pages/app.dart';
import 'package:obtainium/pages/logs.dart';
import 'package:obtainium/pages/settings.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// Edge behavior for pushed routes.
///
/// On TV, focus must stay inside the current page: with the framework default
/// (`parentScope`) pressing a direction at the edge of a pushed page moves
/// focus into the inactive route behind it, which is invisible and
/// disorienting. Touch devices keep the default behavior.
TraversalEdgeBehavior traversalEdgeBehaviorFor(BuildContext context) =>
    context.read<SettingsProvider>().isTV
    ? TraversalEdgeBehavior.stop
    : TraversalEdgeBehavior.parentScope;

class NavHelper {
  NavHelper._();

  static void pushAppPage(
    BuildContext context,
    String appId, {
    bool showOppositeOfPreferredView = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        traversalEdgeBehavior: traversalEdgeBehaviorFor(context),
        builder: (_) => AppPage(
          appId: appId,
          showOppositeOfPreferredView: showOppositeOfPreferredView,
        ),
      ),
    );
  }

  static void pushSettingsPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        traversalEdgeBehavior: traversalEdgeBehaviorFor(context),
        builder: (_) => const SettingsPage(),
      ),
    );
  }

  static void pushAddAppPage(BuildContext context, {String? initialUrl}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        traversalEdgeBehavior: traversalEdgeBehaviorFor(context),
        builder: (_) => AddAppPage(initialUrl: initialUrl),
      ),
    );
  }

  static void pushLogsPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        traversalEdgeBehavior: traversalEdgeBehaviorFor(context),
        builder: (_) => const LogsPage(),
      ),
    );
  }
}
