import 'package:flutter/widgets.dart';

/// Spatial (geometric) D-pad navigation, as expected on a TV: pressing a
/// direction moves focus to the nearest focusable widget in that direction.
///
/// The default reading-order policy produces surprising jumps on large,
/// multi-column layouts (and never crosses cleanly between the app list and
/// the detail pane). Geometric navigation makes a two-pane layout behave the
/// way a remote-control user expects: right enters the detail pane, left
/// returns to the list.
class TvDirectionalTraversalPolicy extends FocusTraversalPolicy
    with DirectionalFocusTraversalPolicyMixin {
  TvDirectionalTraversalPolicy();

  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) => descendants;
}
