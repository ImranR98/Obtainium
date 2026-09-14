import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

export 'generated_form_model.dart';

typedef OnValueChanges =
    void Function(Map<String, dynamic> values, bool valid, bool isBuilding);

class GeneratedForm extends StatefulWidget {
  const GeneratedForm({
    super.key,
    required this.items,
    required this.onValueChanges,
    this.tileMode = false,
    this.noTilePadding = false,
  });

  final List<List<GeneratedFormItem>> items;
  final OnValueChanges onValueChanges;

  final bool tileMode;
  final bool noTilePadding;

  @override
  State<GeneratedForm> createState() => _GeneratedFormState();
}

/// Whether a text field currently owns focus with the keyboard open.
///
/// Page-level [PopScope]s that react to BACK by navigating away should check
/// this first: while editing, the first BACK press is consumed by
/// [TvTextFieldFocus] to dismiss the on-screen keyboard, but the framework
/// notifies every registered `PopScope` on the route, so without this guard a
/// "save on leave" page would exit at the same time.
bool isEditingTextField() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null;
}

class TvTextFieldFocus extends StatefulWidget {
  final Widget child;
  final FocusNode textFocusNode;
  final double borderRadius;

  const TvTextFieldFocus({
    super.key,
    required this.child,
    required this.textFocusNode,
    this.borderRadius = 4,
  });

  @override
  State<TvTextFieldFocus> createState() => _TvTextFieldFocusState();
}

class _TvTextFieldFocusState extends State<TvTextFieldFocus> {
  final FocusNode _outerFocus = FocusNode();
  bool _activated = false;

  @override
  void initState() {
    super.initState();
    widget.textFocusNode.addListener(_onTextFocusChange);
  }

  @override
  void didUpdateWidget(covariant TvTextFieldFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.textFocusNode != oldWidget.textFocusNode) {
      oldWidget.textFocusNode.removeListener(_onTextFocusChange);
      widget.textFocusNode.addListener(_onTextFocusChange);
    }
  }

  void _onTextFocusChange() {
    if (!widget.textFocusNode.hasFocus && _activated) {
      setState(() => _activated = false);
      _outerFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    widget.textFocusNode.removeListener(_onTextFocusChange);
    _outerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_activated,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _activated) {
          setState(() => _activated = false);
          widget.textFocusNode.unfocus();
          _outerFocus.requestFocus();
        }
      },
      child: Focus(
        focusNode: _outerFocus,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter)) {
            setState(() => _activated = true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.textFocusNode.requestFocus();
            });
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ListenableBuilder(
          listenable: _outerFocus,
          builder: (context, child) => Container(
            decoration: _outerFocus.hasFocus && !_activated
                ? BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                  )
                : null,
            child: ExcludeFocus(excluding: !_activated, child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _GeneratedFormState extends State<GeneratedForm> {
  Map<String, dynamic> values = {};
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, GlobalKey<FormFieldState>> _fieldKeys = {};
  final Map<String, int> _subFormGenerations = {};

  InputDecoration _fieldDecoration({
    required String labelText,
    String? hintText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      suffixIcon: suffixIcon,
      suffixIconConstraints: widget.tileMode
          ? const BoxConstraints(minWidth: 0, minHeight: 0)
          : null,
    );
  }

  Widget? _buildHelpSuffixIcon(String? helpUrl) {
    if (helpUrl != null) {
      return IconButton(
        icon: const Icon(Icons.open_in_new),
        tooltip: tr('about'),
        onPressed: () => unawaited(
          launchUrlString(helpUrl, mode: LaunchMode.externalApplication),
        ),
      );
    }
    return null;
  }

  void notifyFormChange({bool forceInvalid = false, bool isBuilding = false}) {
    final Map<String, dynamic> returnValues = values;
    var valid = true;
    // Validity is computed even for the initial post-frame (isBuilding) pass:
    // FormFieldState.isValid is synchronous, so the fields are already mounted.
    // Callers use isBuilding to skip side effects, but the reported validity
    // must be real (e.g. GeneratedFormModal enables its primary action).
    for (final key in _fieldKeys.values) {
      valid = valid && key.currentState?.isValid == true;
    }
    if (forceInvalid) {
      valid = false;
    }
    widget.onValueChanges(returnValues, valid, isBuilding);
  }

  Widget _buildTextField(GeneratedFormTextField formItem) {
    final fieldKey = formItem.key;
    final formFieldKey = _fieldKeys.putIfAbsent(
      fieldKey,
      () => GlobalKey<FormFieldState>(),
    );
    final ctrl = _textControllers.putIfAbsent(
      fieldKey,
      () => TextEditingController(text: values[fieldKey]?.toString() ?? ''),
    );
    return TypeAheadField<String>(
      controller: ctrl,
      builder: (context, controller, focusNode) {
        final textField = TextFormField(
          controller: ctrl,
          focusNode: focusNode,
          obscureText: formItem.password,
          autocorrect: !formItem.password,
          enableSuggestions: !formItem.password,
          key: formFieldKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          onChanged: (value) {
            setState(() {
              values[fieldKey] = value;
              notifyFormChange();
            });
          },
          decoration: _fieldDecoration(
            labelText: tr(formItem.label) + (formItem.required ? ' *' : ''),
            hintText: formItem.hint,
            suffixIcon: _buildHelpSuffixIcon(formItem.helpUrl),
          ),
          minLines: formItem.max <= 1 ? null : formItem.max,
          maxLines: formItem.max <= 1 ? 1 : formItem.max,
          validator: (value) {
            if (formItem.required && (value == null || value.trim().isEmpty)) {
              return '${tr(formItem.label)} ${tr('requiredInBrackets')}\n';
            }
            for (var validator in formItem.additionalValidators) {
              final String? result = validator(value);
              if (result != null) {
                return '$result\n';
              }
            }
            return null;
          },
        );
        if (context.read<SettingsProvider>().isTV) {
          return TvTextFieldFocus(textFocusNode: focusNode, child: textField);
        }
        return textField;
      },
      itemBuilder: (context, value) {
        return ListTile(title: Text(value));
      },
      decorationBuilder: (context, child) => LegacyMaterialBridge(
        child: Material(
          type: MaterialType.card,
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: child,
        ),
      ),
      onSelected: (value) {
        ctrl.text = value;
        setState(() {
          values[fieldKey] = value;
          notifyFormChange();
        });
      },
      suggestionsCallback: (search) {
        return formItem.autoCompleteOptions
            ?.where((t) => t.toLowerCase().contains(search.toLowerCase()))
            .toList();
      },
      hideOnEmpty: true,
    );
  }

  Widget _buildDropdown(GeneratedFormDropdown formItem) {
    if (formItem.opts == null || formItem.opts!.isEmpty) {
      return Text(tr('dropdownNoOptsError'));
    }
    return TvFocusRing(
      borderRadius: 16,
      child: DropdownButtonFormField(
        decoration: _fieldDecoration(
          labelText: tr(formItem.label) + (formItem.required ? ' *' : ''),
          suffixIcon: _buildHelpSuffixIcon(formItem.helpUrl),
        ),
        initialValue: values[formItem.key],
        items: formItem.opts!.map((e2) {
          return DropdownMenuItem(value: e2.key, child: Text(tr(e2.value)));
        }).toList(),
        onChanged: (value) {
          setState(() {
            values[formItem.key] = value ?? values[formItem.key];
            notifyFormChange();
          });
        },
      ),
    );
  }

  Widget _buildSlider(GeneratedFormSlider formItem) {
    return _SliderFormItem(
      formItem: formItem,
      initialValue: values[formItem.key],
      onCommit: (value) {
        setState(() {
          values[formItem.key] = value;
          notifyFormChange();
        });
      },
    );
  }

  /// Expands the sub-form's saved entries into [values], filling any missing
  /// keys with the item defaults.
  void _initSubFormValues(GeneratedFormSubForm formItem) {
    final List<Map<String, dynamic>> entries = [];
    final initValue = formItem.value;
    if (initValue is List) {
      for (Map<String, dynamic> v in initValue.cast<Map<String, dynamic>>()) {
        final fullDefaults = getDefaultValuesFromFormItems(formItem.items);
        for (var element in v.entries) {
          fullDefaults[element.key] = element.value;
        }
        entries.add(fullDefaults);
      }
    }
    values[formItem.key] = entries;
  }

  /// Signature of the form's structure, used to detect when [values] and the
  /// field controllers must be re-initialized after a widget update.
  int _itemsSignature(List<List<GeneratedFormItem>> items) {
    return Object.hashAll(
      items.expand((row) => row.map((e) => Object.hash(e.key, e.runtimeType))),
    );
  }

  void _initFormData() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    _textControllers.clear();
    _fieldKeys.clear();
    _subFormGenerations.clear();
    values = {
      for (final row in widget.items)
        for (final item in row) item.key: item.value,
    };
    for (final row in widget.items) {
      for (final item in row) {
        if (item is GeneratedFormSubForm) {
          _initSubFormValues(item);
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _initFormData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      notifyFormChange(isBuilding: true);
    });
  }

  @override
  void didUpdateWidget(covariant GeneratedForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_itemsSignature(widget.items) != _itemsSignature(oldWidget.items)) {
      _initFormData();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        notifyFormChange(isBuilding: true);
      });
      return;
    }
    // Sync item-level default changes (e.g. a search field whose prefill
    // depends on another field's host) without resetting the whole form.
    final oldValues = <String, dynamic>{
      for (final row in oldWidget.items)
        for (final item in row) item.key: item.value,
    };
    var changed = false;
    for (final row in widget.items) {
      for (final item in row) {
        if (!oldValues.containsKey(item.key) ||
            oldValues[item.key] == item.value) {
          continue;
        }
        if (item is GeneratedFormTextField) {
          values[item.key] = item.value;
          final controller = _textControllers[item.key];
          final text = item.value?.toString() ?? '';
          if (controller != null && controller.text != text) {
            controller.text = text;
          }
          changed = true;
        } else if (item is GeneratedFormSwitch) {
          values[item.key] = item.value;
          changed = true;
        }
      }
    }
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        notifyFormChange(isBuilding: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    _fieldKeys.clear();
    super.dispose();
  }

  Widget _buildSubForm(
    GeneratedFormSubForm item,
    String fieldKey, {
    bool isFirst = true,
    bool isLast = true,
  }) {
    final compact = item.items.length == 1 && item.items[0].length == 1;
    final List<Map<String, dynamic>> entries =
        values[fieldKey] as List<Map<String, dynamic>>;
    final n = entries.length;
    // Bumping the generation changes every child's key, so all entries are
    // re-initialized from [values] after a structural add/remove instead of
    // reusing another entry's field state.
    final generation = _subFormGenerations[fieldKey] ?? 0;
    final List<Widget> cards = [];
    for (int i = 0; i < n; i++) {
      final isLastEntry = i == n - 1;
      cards.add(
        ConnectedCard(
          isFirst: i == 0 ? isFirst : false,
          isLast: isLastEntry ? isLast : false,
          padding: null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!compact) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    '${tr(item.label)} (${i + 1})',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              GeneratedForm(
                key: ValueKey('$fieldKey#$i#$generation'),
                noTilePadding: widget.noTilePadding,
                items: cloneFormItems(item.items)
                    .map(
                      (x) => x.map((y) {
                        y.value = entries[i][y.key];
                        return y;
                      }).toList(),
                    )
                    .toList(),
                onValueChanges: (subValues, valid, isBuilding) {
                  if (valid) {
                    entries[i] = subValues;
                  }
                  notifyFormChange(
                    forceInvalid: !valid,
                    isBuilding: isBuilding,
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      style: IconButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      visualDensity: VisualDensity.compact,
                      tooltip: tr('remove'),
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () {
                        final temp = List<Map<String, dynamic>>.from(entries);
                        temp.removeAt(i);
                        values[fieldKey] = temp;
                        _subFormGenerations[fieldKey] = generation + 1;
                        setState(() {});
                        notifyFormChange();
                      },
                    ),
                    const Spacer(),
                    if (isLastEntry)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                        ),
                        onPressed: () {
                          entries.add(
                            getDefaultValuesFromFormItems(item.items),
                          );
                          _subFormGenerations[fieldKey] = generation + 1;
                          setState(() {});
                          notifyFormChange();
                        },
                        icon: const Icon(Icons.add),
                        label: Text(tr(item.label)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (n == 0) {
      cards.add(
        ConnectedCard(
          isFirst: isFirst,
          isLast: isLast,
          padding: null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: () {
                    entries.add(getDefaultValuesFromFormItems(item.items));
                    _subFormGenerations[fieldKey] = generation + 1;
                    setState(() {});
                    notifyFormChange();
                  },
                  icon: const Icon(Icons.add),
                  label: Text(tr(item.label)),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 3,
      children: cards,
    );
  }

  Widget _buildItem(
    GeneratedFormItem item, {
    required bool isFirst,
    required bool isLast,
  }) {
    if (item is GeneratedFormTextField) return _buildTextField(item);
    if (item is GeneratedFormDropdown) return _buildDropdown(item);
    if (item is GeneratedFormSlider) return _buildSlider(item);
    if (item is GeneratedFormSwitch) {
      return ToggleTile(
        label: tr(item.label),
        value: values[item.key] as bool,
        noPadding: widget.noTilePadding,
        onChanged: item.disabled
            ? null
            : hapticSwitchOnChanged(context, (value) {
                setState(() {
                  values[item.key] = value;
                  notifyFormChange();
                });
              }),
      );
    }
    if (item is GeneratedFormSubForm) {
      return _buildSubForm(item, item.key, isFirst: isFirst, isLast: isLast);
    }
    throw ObtainiumError(
      'Unrecognized form item type: ${item.runtimeType}',
      unexpected: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> inputRowWidgets = [];
    for (var r = 0; r < widget.items.length; r++) {
      final List<Widget> rowItems = [];
      for (var e = 0; e < widget.items[r].length; e++) {
        if (e > 0) {
          rowItems.add(const SizedBox(width: 20));
        }
        rowItems.add(
          Expanded(
            child: _buildItem(
              widget.items[r][e],
              isFirst: r == 0,
              isLast: r == widget.items.length - 1,
            ),
          ),
        );
      }
      inputRowWidgets.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rowItems,
        ),
      );
    }

    if (widget.tileMode) {
      bool isFieldRow(int r) =>
          widget.items[r].isNotEmpty &&
          (widget.items[r][0] is GeneratedFormTextField ||
              widget.items[r][0] is GeneratedFormDropdown ||
              widget.items[r][0] is GeneratedFormSlider);
      bool isSubFormRow(int r) =>
          widget.items[r].isNotEmpty &&
          widget.items[r][0] is GeneratedFormSubForm;
      final colorScheme = Theme.of(context).colorScheme;
      final n = inputRowWidgets.length;
      final List<Widget> rawTiles = [];
      for (var r = 0; r < n; r++) {
        if (isSubFormRow(r)) {
          rawTiles.add(inputRowWidgets[r]);
        } else {
          rawTiles.add(
            ConnectedCard(
              isFirst: r == 0,
              isLast: r == n - 1,
              color: isFieldRow(r)
                  ? colorScheme.surfaceContainerHighest
                  : colorScheme.surfaceContainerLow,
              child: inputRowWidgets[r],
            ),
          );
        }
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 3,
        children: rawTiles,
      );
    }

    final List<Widget> children = [];
    for (var r = 0; r < inputRowWidgets.length; r++) {
      if (r > 0) {
        children.add(const SizedBox(height: 8));
      }
      children.add(inputRowWidgets[r]);
    }

    return Column(children: children);
  }
}

/// A discrete-value slider backed by a [GeneratedFormSlider]. Kept as its own
/// [StatefulWidget] so dragging only rebuilds the slider; the chosen value is
/// committed to the form when the drag ends (or per step on TV).
class _SliderFormItem extends StatefulWidget {
  const _SliderFormItem({
    required this.formItem,
    required this.initialValue,
    required this.onCommit,
  });

  final GeneratedFormSlider formItem;
  final dynamic initialValue;
  final ValueChanged<String> onCommit;

  @override
  State<_SliderFormItem> createState() => _SliderFormItemState();
}

class _SliderFormItemState extends State<_SliderFormItem> {
  late final List<MapEntry<String, String>> opts;
  late double sliderVal;
  bool showLabel = true;

  int get _index => sliderVal.round().clamp(0, opts.length - 1);

  String _optLabel(MapEntry<String, String> opt) {
    final days = int.tryParse(opt.value);
    return days != null ? plural('day', days) : tr(opt.value);
  }

  String get _label => _optLabel(opts[_index]);

  @override
  void initState() {
    super.initState();
    opts = widget.formItem.opts ?? const <MapEntry<String, String>>[];
    final index = opts.indexWhere((e) => e.key == widget.initialValue);
    sliderVal = (index >= 0 ? index : 0).toDouble();
  }

  void _commit() {
    widget.onCommit(opts[_index].key);
  }

  @override
  Widget build(BuildContext context) {
    final max = (opts.length - 1).toDouble();
    final settingsProvider = context.read<SettingsProvider>();
    final Widget slider = settingsProvider.isTV
        ? Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: sliderVal <= 0
                    ? null
                    : () {
                        setState(() {
                          sliderVal = (sliderVal - 1).clamp(0.0, max);
                        });
                        _commit();
                      },
              ),
              Expanded(child: Text(_label, textAlign: TextAlign.center)),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: sliderVal >= max
                    ? null
                    : () {
                        setState(() {
                          sliderVal = (sliderVal + 1).clamp(0.0, max);
                        });
                        _commit();
                      },
              ),
            ],
          )
        : Slider(
            value: sliderVal,
            max: max,
            divisions: opts.length - 1,
            label: _label,
            onChanged: (double value) {
              setState(() {
                sliderVal = value;
              });
            },
            onChangeStart: (double value) {
              setState(() {
                showLabel = false;
              });
            },
            onChangeEnd: (double value) {
              setState(() {
                showLabel = true;
              });
              _commit();
            },
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          showLabel
              ? Text('${tr(widget.formItem.label)}: $_label')
              : const SizedBox(height: 20),
          slider,
        ],
      ),
    );
  }
}

class GeneratedFormModal extends StatefulWidget {
  const GeneratedFormModal({
    super.key,
    required this.title,
    required this.items,
    this.initValid = false,
    this.message = '',
    this.additionalWidgets = const [],
    this.singleNullReturnButton,
    this.primaryActionColour,
    this.tileMode = false,
    this.onValueChanges,
  });

  final String title;
  final String message;
  final List<List<GeneratedFormItem>> items;
  final bool initValid;
  final List<Widget> additionalWidgets;
  final String? singleNullReturnButton;
  final Color? primaryActionColour;
  final bool tileMode;

  /// Called in addition to the modal's own state tracking, e.g. so callers
  /// can rebuild [items] when a field changes.
  final OnValueChanges? onValueChanges;

  @override
  State<GeneratedFormModal> createState() => _GeneratedFormModalState();
}

class _GeneratedFormModalState extends State<GeneratedFormModal> {
  Map<String, dynamic> values = {};
  bool valid = false;

  @override
  void initState() {
    super.initState();
    valid = widget.initValid || widget.items.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.message.isNotEmpty) Text(widget.message),
          if (widget.message.isNotEmpty) const SizedBox(height: 16),
          GeneratedForm(
            tileMode: widget.tileMode,
            noTilePadding: true,
            items: widget.items,
            onValueChanges: (values, valid, isBuilding) {
              // The callback fires from a post-frame callback (not during
              // build), so setState is always safe here - including for the
              // initial isBuilding pass, which keeps the OK button's validity
              // correct on first render.
              if (!mounted) return;
              widget.onValueChanges?.call(values, valid, isBuilding);
              setState(() {
                this.values = values;
                this.valid = valid;
              });
            },
          ),
          if (widget.additionalWidgets.isNotEmpty) ...widget.additionalWidgets,
        ],
      ),
      actions: [
        TextButton(
          autofocus: context.read<SettingsProvider>().isTV,
          onPressed: () {
            Navigator.of(context).pop(null);
          },
          child: Text(
            widget.singleNullReturnButton == null
                ? tr('cancel')
                : widget.singleNullReturnButton!,
          ),
        ),
        widget.singleNullReturnButton == null
            ? FilledButton(
                style: widget.primaryActionColour == null
                    ? null
                    : FilledButton.styleFrom(
                        backgroundColor: widget.primaryActionColour,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      ),
                onPressed: !valid
                    ? null
                    : () {
                        context.read<SettingsProvider>().selectionClick();
                        Navigator.of(context).pop(values);
                      },
                child: Text(tr('continue')),
              )
            : const SizedBox.shrink(),
      ],
    );
  }
}
