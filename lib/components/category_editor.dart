import 'package:easy_localization/easy_localization.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:obtainium/components/generated_form_renderer.dart'
    show generateRandomLightColor;
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';
import 'package:provider/provider.dart';

/// A small curated palette of pleasant category colours for quick picking.
const List<Color> kCategoryPalette = [
  Color(0xFFEF5350),
  Color(0xFFFF7043),
  Color(0xFFFFA726),
  Color(0xFFFFCA28),
  Color(0xFF9CCC65),
  Color(0xFF66BB6A),
  Color(0xFF26A69A),
  Color(0xFF26C6DA),
  Color(0xFF29B6F6),
  Color(0xFF42A5F5),
  Color(0xFF5C6BC0),
  Color(0xFF7E57C2),
  Color(0xFFAB47BC),
  Color(0xFFEC407A),
  Color(0xFF8D6E63),
  Color(0xFF78909C),
];

/// The outcome of editing a category via [showCategoryEditor].
class CategoryEditResult {
  /// The resulting category name; null if the category was deleted.
  final String? name;

  /// The name being edited (null when creating); lets callers migrate any
  /// selection that referenced the old name.
  final String? previous;

  const CategoryEditResult({this.name, this.previous});
}

/// Opens the bottom-sheet editor to create (when [existingName] is null) or
/// edit/recolor/rename/delete a category. Persists changes to the global
/// category registry (migrating app references on rename, pruning on delete)
/// and returns what happened, or null if cancelled.
Future<CategoryEditResult?> showCategoryEditor(
  BuildContext context, {
  String? existingName,
}) {
  final registry = context.read<SettingsProvider>().categories;
  final initialColor = existingName != null && registry[existingName] != null
      ? Color(registry[existingName]!)
      : generateRandomLightColor();
  return showModalBottomSheet<CategoryEditResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _CategoryEditorSheet(
      existingName: existingName,
      initialColor: initialColor,
    ),
  );
}

class _CategoryEditorSheet extends StatefulWidget {
  final String? existingName;
  final Color initialColor;

  const _CategoryEditorSheet({this.existingName, required this.initialColor});

  @override
  State<_CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends State<_CategoryEditorSheet> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.existingName ?? '',
  );
  late final ValueNotifier<String> _nameNotifier = ValueNotifier(
    widget.existingName ?? '',
  );
  late Color _color = widget.initialColor;

  bool get _isEditing => widget.existingName != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameNotifier.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final settingsProvider = context.read<SettingsProvider>();
    final appsProvider = context.read<AppsProvider>();
    final cats = Map<String, int>.from(settingsProvider.categories);
    final prev = widget.existingName;
    // Creating a category whose name already exists must not overwrite the
    // existing one's color (matches main, which no-ops on duplicates).
    if (prev == null && cats.containsKey(name)) {
      if (context.mounted) {
        showMessage(tr('categoryAlreadyExists'), context);
      }
      return;
    }
    if (prev != null && prev != name) {
      cats.remove(prev);
      // Migrate apps that referenced the old name so the rename is preserved.
      final changed = <App>[];
      for (final aim in appsProvider.apps.values) {
        if (aim.app.categories.contains(prev)) {
          aim.app = aim.app.copyWith(
            categories: aim.app.categories
                .map((c) => c == prev ? name : c)
                .toList(),
          );
          changed.add(aim.app);
        }
      }
      if (changed.isNotEmpty) await appsProvider.saveApps(changed);
    }
    cats[name] = _color.toARGB32();
    settingsProvider.setCategories(cats, appsProvider: appsProvider);
    if (context.mounted) {
      // ignore: use_build_context_synchronously
      Navigator.of(context).pop(CategoryEditResult(name: name, previous: prev));
    }
  }

  Future<void> _delete() async {
    final appsProvider = context.read<AppsProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    final confirmed = await showConfirmDialog(
      context,
      title: tr('deleteCategoriesQuestion'),
      content: Text(tr('categoryDeleteWarning')),
      autofocusConfirm: context.read<SettingsProvider>().isTV,
    );
    if (!confirmed) return;
    final cats = Map<String, int>.from(settingsProvider.categories)
      ..remove(widget.existingName);
    settingsProvider.setCategories(cats, appsProvider: appsProvider);
    if (mounted) {
      Navigator.of(
        context,
      ).pop(CategoryEditResult(name: null, previous: widget.existingName));
    }
  }

  Future<void> _pickCustomColor() async {
    var picked = _color;
    final ok = await ColorPicker(
      color: _color,
      onColorChanged: (c) => picked = c,
      actionButtons: const ColorPickerActionButtons(
        okButton: true,
        closeButton: true,
        dialogActionButtons: false,
      ),
      pickersEnabled: const <ColorPickerType, bool>{
        ColorPickerType.both: false,
        ColorPickerType.primary: false,
        ColorPickerType.accent: false,
        ColorPickerType.bw: false,
        ColorPickerType.custom: false,
        ColorPickerType.wheel: true,
      },
      title: Text(
        tr('selectX', args: [lowerCaseUnlessLang(tr('colour'), 'de')]),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      wheelDiameter: 192,
      wheelSquareBorderRadius: 32,
      borderRadius: 24,
      enableShadesSelection: false,
    ).showPickerDialog(context);
    if (ok && context.mounted) setState(() => _color = picked);
  }

  Widget _swatch({
    required Color color,
    required bool selected,
    required VoidCallback onTap,
    Widget? icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? cs.onSurface : cs.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: icon == null
              ? (selected
                    ? Icon(
                        Icons.check,
                        size: 20,
                        color:
                            ThemeData.estimateBrightnessForColor(color) ==
                                Brightness.dark
                            ? Colors.white
                            : Colors.black,
                      )
                    : null)
              : Center(child: icon),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isEditing ? tr('editCategory') : tr('newCategory'),
            style: textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          ConnectedCard(
            child: TextField(
              controller: _nameCtrl,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('categoryName')),
              onChanged: (value) => _nameNotifier.value = value,
              onSubmitted: (_) {
                if (_nameCtrl.text.trim().isNotEmpty) _save();
              },
            ),
          ),
          const SizedBox(height: 20),
          Text(tr('colour'), style: textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in kCategoryPalette)
                _swatch(
                  color: c,
                  selected: c.toARGB32() == _color.toARGB32(),
                  onTap: () => setState(() => _color = c),
                ),
              _swatch(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                selected: false,
                onTap: () =>
                    setState(() => _color = generateRandomLightColor()),
                icon: Tooltip(
                  message: tr('randomColour'),
                  child: const Icon(Icons.casino_outlined, size: 20),
                ),
              ),
              _swatch(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                selected: false,
                onTap: _pickCustomColor,
                icon: Tooltip(
                  message: tr('custom'),
                  child: const Icon(Icons.colorize_outlined, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              if (_isEditing)
                TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(tr('remove')),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(tr('cancel')),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<String>(
                valueListenable: _nameNotifier,
                builder: (context, value, _) {
                  final canSave = value.trim().isNotEmpty;
                  return FilledButton(
                    onPressed: canSave ? _save : null,
                    child: Text(tr('continue')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A multi- (or single-) select field over the global category registry.
///
/// Tapping a chip toggles its selection; long-pressing opens the editor
/// (recolor/rename/delete); the trailing "+ New" chip creates a category (when
/// [allowCreate]). Selection is reported via [onChanged] but never persisted —
/// hosts decide when to apply it, keeping it consistent with other form inputs.
class CategorySelector extends StatefulWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool singleSelect;
  final bool allowCreate;
  final WrapAlignment alignment;

  const CategorySelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.singleSelect = false,
    this.allowCreate = true,
    this.alignment = WrapAlignment.start,
  });

  @override
  State<CategorySelector> createState() => _CategorySelectorState();
}

class _CategorySelectorState extends State<CategorySelector> {
  late Set<String> _selected = {...widget.selected};

  @override
  void didUpdateWidget(CategorySelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected.length != widget.selected.length ||
        !setEquals(oldWidget.selected, widget.selected)) {
      _selected = {...widget.selected};
    }
  }

  void _emit() => widget.onChanged({..._selected});

  void _toggle(String name, bool value) {
    setState(() {
      if (widget.singleSelect) {
        _selected = value ? {name} : {};
      } else if (value) {
        _selected.add(name);
      } else {
        _selected.remove(name);
      }
    });
    _emit();
  }

  Future<void> _create() async {
    final result = await showCategoryEditor(context);
    if (result?.name == null) return;
    if (!context.mounted) return;
    setState(() {
      if (widget.singleSelect) {
        _selected = {result!.name!};
      } else {
        _selected.add(result!.name!);
      }
    });
    _emit();
  }

  Future<void> _edit(String name) async {
    final result = await showCategoryEditor(context, existingName: name);
    if (result == null) return;
    if (!context.mounted) return;
    final wasSelected = _selected.contains(name);
    setState(() {
      _selected.remove(name);
      if (result.name != null && wasSelected) _selected.add(result.name!);
    });
    if (wasSelected) _emit();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final categories = context.select<SettingsProvider, Map<String, int>>(
      (p) => p.categories,
    );
    final names = categories.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final prunedSelected = _selected.where(categories.containsKey).toSet();
    if (prunedSelected.length != _selected.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          setState(() {
            _selected = prunedSelected;
          });
          _emit();
        }
      });
    }

    if (names.isEmpty && !widget.allowCreate) {
      return Text(
        tr('noCategories'),
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      );
    }

    if (names.isEmpty && widget.allowCreate) {
      return Wrap(
        alignment: widget.alignment,
        spacing: 8,
        runSpacing: 8,
        children: [
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: Text(tr('newCategory')),
            onPressed: _create,
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            alignment: widget.alignment,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in names)
                Tooltip(
                  message: tr('editCategory'),
                  child: Semantics(
                    onLongPress: () => _edit(name),
                    child: GestureDetector(
                      onLongPress: () => _edit(name),
                      child: FilterChip(
                        avatar: CircleAvatar(
                          backgroundColor:
                              Color(categories[name] ?? 0xFFCCCCCC),
                          radius: 7,
                        ),
                        label: Text(name),
                        selected: _selected.contains(name),
                        onSelected: (v) => _toggle(name, v),
                        selectedColor: Color(
                          categories[name] ?? 0xFFCCCCCC,
                        ).withValues(alpha: 0.22),
                        showCheckmark: true,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.allowCreate) const SizedBox(width: 8),
        if (widget.allowCreate)
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: Text(tr('newCategory')),
            onPressed: _create,
          ),
      ],
    );
  }
}

/// Manage-only view of the category registry (used in Settings): every category
/// is an editable chip (tap to recolor/rename/delete) plus a "+ New" action.
class CategoryManager extends StatelessWidget {
  const CategoryManager({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final categories = context.watch<SettingsProvider>().categories;
    final names = categories.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (names.isEmpty) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            tr('noCategories'),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const Spacer(),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: Text(tr('newCategory')),
            onPressed: () => showCategoryEditor(context),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final name in names)
                ActionChip(
                  avatar: CircleAvatar(
                    backgroundColor: Color(categories[name]!),
                    radius: 7,
                  ),
                  label: Text(name),
                  onPressed: () =>
                      showCategoryEditor(context, existingName: name),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: Text(tr('newCategory')),
          onPressed: () => showCategoryEditor(context),
        ),
      ],
    );
  }
}
