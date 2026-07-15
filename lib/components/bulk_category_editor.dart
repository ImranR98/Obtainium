import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/components/app_bottom_sheet.dart';
import 'package:obtainium/components/category_action_chip.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/components/generated_form_renderer.dart';

enum BulkCategoryCoverageState { all, some, none }

enum BulkCategoryIntent { neutral, add, remove }

class BulkCategoryCoverage {
  const BulkCategoryCoverage({
    required this.category,
    required this.matchCount,
    required this.totalCount,
    required this.state,
  });

  final String category;
  final int matchCount;
  final int totalCount;
  final BulkCategoryCoverageState state;
}

class BulkCategoryIntentActions {
  const BulkCategoryIntentActions({
    required this.addCategories,
    required this.removeCategories,
    required this.newCategoryColors,
  });

  final Set<String> addCategories;
  final Set<String> removeCategories;
  final Map<String, int> newCategoryColors;

  bool get hasPending =>
      addCategories.isNotEmpty || removeCategories.isNotEmpty;
}

String bulkCategoryKey(String category) => category.trim().toLowerCase();

List<BulkCategoryCoverage> buildBulkCategoryCoverage({
  required Map<String, int> availableCategoryColors,
  required Iterable<Iterable<String>> selectedAppCategories,
  Iterable<String> extraCategories = const [],
}) {
  final labelsByKey = <String, String>{};

  void addLabel(String category) {
    final trimmed = category.trim();
    if (trimmed.isEmpty) return;
    labelsByKey.putIfAbsent(bulkCategoryKey(trimmed), () => trimmed);
  }

  for (final category in availableCategoryColors.keys) {
    addLabel(category);
  }
  for (final categories in selectedAppCategories) {
    for (final category in categories) {
      addLabel(category);
    }
  }
  for (final category in extraCategories) {
    addLabel(category);
  }

  final selectedSets = selectedAppCategories
      .map(
        (categories) => categories
            .map((category) => category.trim())
            .where((category) => category.isNotEmpty)
            .map(bulkCategoryKey)
            .toSet(),
      )
      .toList();

  final coverage = labelsByKey.entries.map((entry) {
    final matchCount = selectedSets
        .where((set) => set.contains(entry.key))
        .length;
    return BulkCategoryCoverage(
      category: entry.value,
      matchCount: matchCount,
      totalCount: selectedSets.length,
      state: switch (matchCount) {
        0 => BulkCategoryCoverageState.none,
        final count when count == selectedSets.length =>
          BulkCategoryCoverageState.all,
        _ => BulkCategoryCoverageState.some,
      },
    );
  }).toList();

  coverage.sort(_compareBulkCategoryCoverage);
  return coverage;
}

BulkCategoryIntent nextBulkCategoryIntent(
  BulkCategoryCoverageState state,
  BulkCategoryIntent intent,
) {
  return switch (intent) {
    BulkCategoryIntent.neutral => switch (state) {
      BulkCategoryCoverageState.all => BulkCategoryIntent.remove,
      BulkCategoryCoverageState.some => BulkCategoryIntent.add,
      BulkCategoryCoverageState.none => BulkCategoryIntent.add,
    },
    BulkCategoryIntent.add => switch (state) {
      BulkCategoryCoverageState.some => BulkCategoryIntent.remove,
      BulkCategoryCoverageState.all => BulkCategoryIntent.neutral,
      BulkCategoryCoverageState.none => BulkCategoryIntent.neutral,
    },
    BulkCategoryIntent.remove => BulkCategoryIntent.neutral,
  };
}

BulkCategoryIntentActions resolveBulkCategoryIntentActions({
  required Iterable<BulkCategoryCoverage> coverage,
  required Iterable<String> extraAddedCategories,
  required Map<String, BulkCategoryIntent> categoryIntents,
  required Map<String, int> newCategoryColorsByKey,
}) {
  final labelsByKey = <String, String>{};

  void addLabel(String category) {
    final trimmed = category.trim();
    if (trimmed.isEmpty) return;
    labelsByKey.putIfAbsent(bulkCategoryKey(trimmed), () => trimmed);
  }

  for (final item in coverage) {
    addLabel(item.category);
  }
  for (final category in extraAddedCategories) {
    addLabel(category);
  }

  final addKeys = categoryIntents.entries
      .where((entry) => entry.value == BulkCategoryIntent.add)
      .map((entry) => entry.key)
      .toSet();
  final removeKeys = categoryIntents.entries
      .where((entry) => entry.value == BulkCategoryIntent.remove)
      .map((entry) => entry.key)
      .toSet();

  final addCategories = addKeys
      .map((key) => labelsByKey[key])
      .whereType<String>()
      .toSet();
  final removeCategories = removeKeys
      .map((key) => labelsByKey[key])
      .whereType<String>()
      .toSet();
  final newCategoryColors = <String, int>{};
  for (final key in addKeys) {
    final category = labelsByKey[key];
    final color = newCategoryColorsByKey[key];
    if (category != null && color != null) {
      newCategoryColors[category] = color;
    }
  }

  return BulkCategoryIntentActions(
    addCategories: addCategories,
    removeCategories: removeCategories,
    newCategoryColors: newCategoryColors,
  );
}

List<List<String>> applyBulkCategoryActionsToCategoryLists(
  Iterable<Iterable<String>> categoryLists,
  BulkCategoryIntentActions actions,
) {
  final removeKeys = actions.removeCategories.map(bulkCategoryKey).toSet();
  final additions = actions.addCategories.toList();
  return categoryLists.map((categories) {
    final result = categories
        .where((category) => !removeKeys.contains(bulkCategoryKey(category)))
        .toList();
    final existingKeys = result.map(bulkCategoryKey).toSet();
    for (final category in additions) {
      final key = bulkCategoryKey(category);
      if (key.isNotEmpty && existingKeys.add(key)) {
        result.add(category);
      }
    }
    return result;
  }).toList();
}

int _compareBulkCategoryCoverage(
  BulkCategoryCoverage first,
  BulkCategoryCoverage second,
) {
  int group(BulkCategoryCoverage item) =>
      item.state == BulkCategoryCoverageState.none ? 1 : 0;
  final groupComparison = group(first).compareTo(group(second));
  if (groupComparison != 0) return groupComparison;
  return bulkCategoryKey(
    first.category,
  ).compareTo(bulkCategoryKey(second.category));
}

class BulkCategoryEditorSheet extends StatefulWidget {
  const BulkCategoryEditorSheet({
    super.key,
    required this.availableCategoryColors,
    required this.selectedAppCategories,
    required this.onApply,
  });

  final Map<String, int> availableCategoryColors;
  final List<List<String>> selectedAppCategories;
  final ValueChanged<BulkCategoryIntentActions> onApply;

  @override
  State<BulkCategoryEditorSheet> createState() =>
      _BulkCategoryEditorSheetState();
}

class _BulkCategoryEditorSheetState extends State<BulkCategoryEditorSheet> {
  final List<String> _extraAddedCategories = <String>[];
  final Map<String, BulkCategoryIntent> _categoryIntents =
      <String, BulkCategoryIntent>{};
  final Map<String, int> _newCategoryColorsByKey = <String, int>{};
  late final TextEditingController _newCategoryNameController;
  late Color _newCategoryColor;
  bool _createExpanded = false;

  @override
  void initState() {
    super.initState();
    _newCategoryNameController = TextEditingController();
    _newCategoryColor = generateRandomLightColor();
  }

  @override
  void dispose() {
    _newCategoryNameController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(BulkCategoryEditorSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
          oldWidget.availableCategoryColors,
          widget.availableCategoryColors,
        ) ||
        !identical(
          oldWidget.selectedAppCategories,
          widget.selectedAppCategories,
        )) {
      _coverageCache = null;
    }
  }

  // Coverage is an O(apps × categories) scan plus a sort. It depends only on the
  // widget's category/app inputs and _extraAddedCategories — NOT on the text
  // field or chip intents — so cache it instead of recomputing on every
  // setState (the new-category name field rebuilds on each keystroke just to
  // toggle its Add button). Invalidated in _stageNewCategory and didUpdateWidget.
  List<BulkCategoryCoverage>? _coverageCache;
  List<BulkCategoryCoverage> get _coverage =>
      _coverageCache ??= buildBulkCategoryCoverage(
        availableCategoryColors: widget.availableCategoryColors,
        selectedAppCategories: widget.selectedAppCategories,
        extraCategories: _extraAddedCategories,
      );

  BulkCategoryIntentActions get _pendingActions =>
      resolveBulkCategoryIntentActions(
        coverage: _coverage,
        extraAddedCategories: _extraAddedCategories,
        categoryIntents: _categoryIntents,
        newCategoryColorsByKey: _newCategoryColorsByKey,
      );

  int _categoryColor(String category) {
    final key = bulkCategoryKey(category);
    final stagedColor = _newCategoryColorsByKey[key];
    if (stagedColor != null) return stagedColor;
    for (final entry in widget.availableCategoryColors.entries) {
      if (bulkCategoryKey(entry.key) == key) return entry.value;
    }
    return Colors.grey.shade500.toARGB32();
  }

  void _stageCategoryHex(String hex) {
    final clean = hex.replaceFirst('#', '');
    final value = int.tryParse(clean, radix: 16);
    if (value == null) return;
    setState(() {
      _newCategoryColor = Color(0xFF000000 | value);
    });
  }

  void _stageNewCategory() {
    final category = _newCategoryNameController.text.trim();
    if (category.isEmpty) return;
    final key = bulkCategoryKey(category);
    final existingCoverage = _coverage.where(
      (item) => bulkCategoryKey(item.category) == key,
    );
    hapticSelection();
    setState(() {
      if (existingCoverage.isEmpty) {
        _extraAddedCategories.add(category);
        _newCategoryColorsByKey[key] = _newCategoryColor.toARGB32();
        _coverageCache = null; // _extraAddedCategories changed → recompute.
      }
      _categoryIntents[key] = BulkCategoryIntent.add;
      _newCategoryNameController.clear();
      _newCategoryColor = generateRandomLightColor();
      _createExpanded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverage = _coverage;
    final pendingActions = _pendingActions;

    return AppSheetContent(
      children: [
        Text(tr('bulkCategorizeTitle'), style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        const _BulkCategorySubtitle(),
        const SizedBox(height: 16),
        if (coverage.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              tr('bulkCategorizeNoExisting'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          CategoryActionChipGroup(
            children: coverage.map((item) {
              final key = bulkCategoryKey(item.category);
              final intent =
                  _categoryIntents[key] ?? BulkCategoryIntent.neutral;
              return _BulkCategoryChip(
                coverage: item,
                color: Color(_categoryColor(item.category)),
                intent: intent,
                onPressed: () {
                  hapticSelection();
                  setState(() {
                    _categoryIntents[key] = nextBulkCategoryIntent(
                      item.state,
                      intent,
                    );
                  });
                },
              );
            }).toList(),
          ),
        const SizedBox(height: 12),
        _CreateCategoryPullTab(
          expanded: _createExpanded,
          onPressed: () {
            hapticSelection();
            setState(() {
              _createExpanded = !_createExpanded;
            });
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: _createExpanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _InlineCategoryCreator(
                    nameController: _newCategoryNameController,
                    color: _newCategoryColor,
                    onNameChanged: (_) => setState(() {}),
                    onColorHexChanged: _stageCategoryHex,
                    onStage: _stageNewCategory,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('cancel')),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: pendingActions.hasPending
                  ? () {
                      widget.onApply(pendingActions);
                      Navigator.pop(context);
                    }
                  : null,
              child: Text(tr('bulkCategorizeApply')),
            ),
          ],
        ),
      ],
    );
  }
}

class _CreateCategoryPullTab extends StatelessWidget {
  const _CreateCategoryPullTab({
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(expanded ? Icons.expand_less : Icons.add),
      label: Text(tr('addCategory')),
    );
  }
}

class _InlineCategoryCreator extends StatelessWidget {
  const _InlineCategoryCreator({
    required this.nameController,
    required this.color,
    required this.onNameChanged,
    required this.onColorHexChanged,
    required this.onStage,
  });

  final TextEditingController nameController;
  final Color color;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onColorHexChanged;
  final VoidCallback onStage;

  @override
  Widget build(BuildContext context) {
    final canStage = nameController.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CategoryEditorFields(
          nameController: nameController,
          color: color,
          autofocusName: true,
          onNameChanged: onNameChanged,
          onColorHexChanged: onColorHexChanged,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: canStage ? onStage : null,
            icon: const Icon(Icons.add),
            label: Text(tr('add')),
          ),
        ),
      ],
    );
  }
}

class _BulkCategorySubtitle extends StatelessWidget {
  const _BulkCategorySubtitle();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.bodyMedium?.copyWith(color: color);
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(tr('bulkCategorizeSubtitleIntro'), style: style),
        Icon(Icons.add, size: 16, color: color),
        Text(tr('bulkCategorizeSubtitleAdd'), style: style),
        Icon(Icons.close, size: 16, color: color),
        Text(tr('bulkCategorizeSubtitleRemove'), style: style),
      ],
    );
  }
}

class _BulkCategoryChip extends StatelessWidget {
  const _BulkCategoryChip({
    required this.coverage,
    required this.color,
    required this.intent,
    required this.onPressed,
  });

  final BulkCategoryCoverage coverage;
  final Color color;
  final BulkCategoryIntent intent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final CategoryActionChipState visualState = switch (intent) {
      BulkCategoryIntent.add => CategoryActionChipState.add,
      BulkCategoryIntent.remove => CategoryActionChipState.remove,
      BulkCategoryIntent.neutral => switch (coverage.state) {
        BulkCategoryCoverageState.all => CategoryActionChipState.selected,
        BulkCategoryCoverageState.some => CategoryActionChipState.partial,
        BulkCategoryCoverageState.none => CategoryActionChipState.unselected,
      },
    };

    return CategoryActionChip(
      onPressed: onPressed,
      label: coverage.category,
      color: color,
      state: visualState,
    );
  }
}
