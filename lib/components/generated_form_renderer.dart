import 'dart:async';
import 'dart:math';

import 'package:hsluv/hsluv.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/components/ui_widgets.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

export 'generated_form_model.dart';

Color generateRandomLightColor() {
  final randomSeed = Random().nextInt(120);
  final goldenAngle = 180 * (3 - sqrt(5));
  final double hue = randomSeed * goldenAngle;
  final List<double> rgbValuesDbl = Hsluv.hpluvToRgb([hue, 100, 70]);
  final List<int> rgbValues = rgbValuesDbl
      .map((rgb) => (rgb * 255).toInt())
      .toList();
  return Color.fromARGB(255, rgbValues[0], rgbValues[1], rgbValues[2]);
}

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
  late List<List<Widget>> formInputs;
  Key? initKey;
  int? _itemsHash;
  int _subFormGenerationCount = 0;
  final List<TextEditingController> _textControllers = [];
  final List<GlobalKey<FormFieldState>> _fieldKeys = [];

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

  Widget? _buildHelpSuffixIcon(
    String label,
    String? helpUrl,
    List<dynamic> belowWidgets,
  ) {
    if (helpUrl != null) {
      return IconButton(
        icon: const Icon(Icons.open_in_new),
        tooltip: tr('about'),
        onPressed: () => unawaited(
          launchUrlString(helpUrl, mode: LaunchMode.externalApplication),
        ),
      );
    }
    if (belowWidgets.isNotEmpty) {
      return IconButton(
        icon: const Icon(Icons.help_outline),
        tooltip: tr('about'),
        onPressed: () => showHelpDialog(
          context,
          title: label,
          content: belowWidgets.cast<Widget>(),
        ),
      );
    }
    return null;
  }

  void notifyFormChange({bool forceInvalid = false, bool isBuilding = false}) {
    final Map<String, dynamic> returnValues = values;
    var valid = true;
    for (final key in _fieldKeys) {
      valid = valid && key.currentState?.isValid == true;
    }
    if (forceInvalid) {
      valid = false;
    }
    widget.onValueChanges(returnValues, valid, isBuilding);
    setState(() {});
  }

  Widget _initTextField(GeneratedFormTextField formItem) {
    final formFieldKey = GlobalKey<FormFieldState>();
    _fieldKeys.add(formFieldKey);
    final ctrl = TextEditingController(text: values[formItem.key]);
    _textControllers.add(ctrl);
    return TypeAheadField<String>(
      controller: ctrl,
      builder: (context, controller, focusNode) {
        final textField = TextFormField(
          controller: ctrl,
          focusNode: focusNode,
          keyboardType: formItem.textInputType,
          obscureText: formItem.password,
          autocorrect: !formItem.password,
          enableSuggestions: !formItem.password,
          key: formFieldKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          onChanged: (value) {
            setState(() {
              values[formItem.key] = value;
              notifyFormChange();
            });
          },
          decoration: _fieldDecoration(
            labelText: tr(formItem.label) + (formItem.required ? ' *' : ''),
            hintText: formItem.hint,
            suffixIcon:
                formItem.trailing ??
                _buildHelpSuffixIcon(
                  tr(formItem.label),
                  formItem.helpUrl,
                  formItem.belowWidgets,
                ),
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
      onSelected: (value) {
        ctrl.text = value;
        setState(() {
          values[formItem.key] = value;
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

  Widget _initDropdown(GeneratedFormDropdown formItem) {
    if (formItem.opts == null || formItem.opts!.isEmpty) {
      return Text(tr('dropdownNoOptsError'));
    }
    return DropdownButtonFormField(
      decoration: _fieldDecoration(
        labelText: tr(formItem.label) + (formItem.required ? ' *' : ''),
        suffixIcon: _buildHelpSuffixIcon(
          tr(formItem.label),
          formItem.helpUrl,
          formItem.belowWidgets,
        ),
      ),
      initialValue: values[formItem.key],
      items: formItem.opts!.map((e2) {
        final enabled = formItem.disabledOptKeys?.contains(e2.key) != true;
        return DropdownMenuItem(
          value: e2.key,
          enabled: enabled,
          child: Opacity(opacity: enabled ? 1 : 0.5, child: Text(tr(e2.value))),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          values[formItem.key] = value ?? values[formItem.key];
          notifyFormChange();
        });
      },
    );
  }

  void _initSubForm(GeneratedFormSubForm formItem) {
    values[formItem.key] = [];
    final initValue = formItem.value;
    if (initValue is! List) return;
    for (Map<String, dynamic> v in initValue.cast<Map<String, dynamic>>()) {
      final fullDefaults = getDefaultValuesFromFormItems(formItem.items);
      for (var element in v.entries) {
        fullDefaults[element.key] = element.value;
      }
      values[formItem.key].add(fullDefaults);
    }
  }

  int _computeItemsHash(List<List<GeneratedFormItem>> items) {
    return Object.hashAll(
      items.expand((row) => row.map((e) {
        return Object.hash(e.key, e.runtimeType,
            e is GeneratedFormTextField ? e.trailingKey : null);
      })),
    );
  }

  void _initFormData() {
    initKey = widget.key;
    _itemsHash = _computeItemsHash(widget.items);
    for (final c in _textControllers) {
      c.dispose();
    }
    _textControllers.clear();
    _fieldKeys.clear();
    values.clear();
    for (var row in widget.items) {
      for (var e in row) {
        values[e.key] = e.value;
      }
    }

    formInputs = widget.items.asMap().entries.map((row) {
      return row.value.asMap().entries.map((e) {
        final formItem = e.value;
        if (formItem is GeneratedFormTextField) {
          return _initTextField(formItem);
        } else if (formItem is GeneratedFormDropdown) {
          return _initDropdown(formItem);
        } else if (formItem is GeneratedFormSubForm) {
          _initSubForm(formItem);
          return Container();
        } else if (formItem is GeneratedFormSwitch) {
          return const SizedBox.shrink();
        } else {
          throw ObtainiumError(
            'Unrecognized form item type: ${formItem.runtimeType}',
            unexpected: true,
          );
        }
      }).toList();
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _initFormData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyFormChange(isBuilding: true);
    });
  }

  @override
  void didUpdateWidget(covariant GeneratedForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.key != initKey ||
        _computeItemsHash(widget.items) != _itemsHash) {
      _initFormData();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyFormChange(isBuilding: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _textControllers) {
      c.dispose();
    }
    _fieldKeys.clear();
    super.dispose();
  }

  Widget _buildSubForm(GeneratedFormSubForm item, String fieldKey,
      {bool isFirst = true, bool isLast = true}) {
    final compact = item.items.length == 1 && item.items[0].length == 1;
    final n = values[fieldKey].length;
    final List<Widget> cards = [];
    for (int i = 0; i < n; i++) {
      final internalFormKey = ValueKey(
        generateDeterministicId(
          n,
          seed2: i,
          seed3: _subFormGenerationCount,
        ),
      );
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
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              GeneratedForm(
                key: internalFormKey,
                noTilePadding: widget.noTilePadding,
                items: cloneFormItems(item.items)
                    .map(
                      (x) => x.map((y) {
                        y.value = values[fieldKey]?[i]?[y.key];
                        y.key = '${y.key.toString()},$internalFormKey';
                        return y;
                      }).toList(),
                    )
                    .toList(),
                onValueChanges: (subValues, valid, isBuilding) {
                  final cleaned = subValues.map(
                    (key, value) => MapEntry(key.split(',')[0], value),
                  );
                  if (valid) {
                    values[fieldKey]?[i] = cleaned;
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
                        foregroundColor:
                            Theme.of(context).colorScheme.error,
                      ),
                      visualDensity: VisualDensity.compact,
                      tooltip: tr('remove'),
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: n > 0
                          ? () {
                              final temp =
                                  List.from(values[fieldKey]);
                              temp.removeAt(i);
                              values[fieldKey] = List.from(temp);
                              _subFormGenerationCount++;
                              notifyFormChange();
                            }
                          : null,
                    ),
                    const Spacer(),
                    if (isLastEntry)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.primary,
                        ),
                        onPressed: () {
                          values[fieldKey].add(
                            getDefaultValuesFromFormItems(
                                item.items),
                          );
                          _subFormGenerationCount++;
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
                    foregroundColor:
                        Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: () {
                    values[fieldKey].add(
                      getDefaultValuesFromFormItems(item.items),
                    );
                    _subFormGenerationCount++;
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

  @override
  Widget build(BuildContext context) {
    final List<List<Widget>> renderedInputs = [
      for (final row in formInputs) [...row],
    ];
    for (var r = 0; r < renderedInputs.length; r++) {
      for (var e = 0; e < renderedInputs[r].length; e++) {
        final item = widget.items[r][e];
        final String fieldKey = item.key;
        if (item is GeneratedFormSwitch) {
          renderedInputs[r][e] = ToggleTile(
            label: tr(item.label),
            value: values[fieldKey] as bool,
            noPadding: widget.noTilePadding,
            onChanged: item.disabled
                ? null
                : (value) {
                    setState(() {
                      values[fieldKey] = value;
                      notifyFormChange();
                    });
                  },
          );
        } else if (item is GeneratedFormSubForm) {
          renderedInputs[r][e] = _buildSubForm(
            item,
            fieldKey,
            isFirst: r == 0,
            isLast: r == widget.items.length - 1,
          );
        }
      }
    }

    final List<Widget> inputRowWidgets = [];
    renderedInputs.asMap().entries.forEach((rowInputs) {
      final List<Widget> rowItems = [];
      rowInputs.value.asMap().entries.forEach((rowInput) {
        if (rowInput.key > 0) {
          rowItems.add(const SizedBox(width: 20));
        }
        rowItems.add(Expanded(child: rowInput.value));
      });
      inputRowWidgets.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rowItems,
        ),
      );
    });

    if (widget.tileMode) {
      bool isFieldRow(int r) =>
          widget.items[r].isNotEmpty &&
          (widget.items[r][0] is GeneratedFormTextField ||
              widget.items[r][0] is GeneratedFormDropdown);
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
  });

  final String title;
  final String message;
  final List<List<GeneratedFormItem>> items;
  final bool initValid;
  final List<Widget> additionalWidgets;
  final String? singleNullReturnButton;
  final Color? primaryActionColour;
  final bool tileMode;

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
