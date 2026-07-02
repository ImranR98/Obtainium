import 'dart:async';
import 'dart:math';

import 'package:hsluv/hsluv.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:obtainium/custom_errors.dart';
import 'package:obtainium/components/generated_form_model.dart';
import 'package:obtainium/theme.dart';
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

bool validateTextField(TextFormField tf) =>
    (tf.key as GlobalKey<FormFieldState>).currentState?.isValid == true;

typedef OnValueChanges =
    void Function(Map<String, dynamic> values, bool valid, bool isBuilding);

class GeneratedForm extends StatefulWidget {
  const GeneratedForm({
    super.key,
    required this.items,
    required this.onValueChanges,
    this.tileMode = false,
    this.fieldDefinitions,
    this.fieldStates,
  });

  GeneratedForm.fromDefinitions({
    super.key,
    required List<FormFieldDefinition> definitions,
    required Map<String, GeneratedFormFieldState> states,
    required this.onValueChanges,
    this.tileMode = false,
    this.fieldDefinitions,
    this.fieldStates,
  }) : items = [definitions.map((d) => d.toGeneratedFormItem()).toList()];

  final List<List<GeneratedFormItem>> items;
  final List<FormFieldDefinition>? fieldDefinitions;
  final Map<String, GeneratedFormFieldState>? fieldStates;
  final OnValueChanges onValueChanges;

  final bool tileMode;

  @override
  State<GeneratedForm> createState() => _GeneratedFormState();
}

class _TVTextFieldFocus extends StatefulWidget {
  final Widget child;
  final FocusNode textFocusNode;

  const _TVTextFieldFocus({required this.child, required this.textFocusNode});

  @override
  State<_TVTextFieldFocus> createState() => _TVTextFieldFocusState();
}

class _TVTextFieldFocusState extends State<_TVTextFieldFocus> {
  final FocusNode _outerFocus = FocusNode();
  bool _activated = false;

  @override
  void initState() {
    super.initState();
    widget.textFocusNode.addListener(_onTextFocusChange);
  }

  @override
  void didUpdateWidget(covariant _TVTextFieldFocus oldWidget) {
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
    return Focus(
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
                  borderRadius: BorderRadius.circular(4),
                )
              : null,
          child: ExcludeFocus(excluding: !_activated, child: widget.child),
        ),
      ),
    );
  }
}

class _FormSwitchRow extends StatelessWidget {
  const _FormSwitchRow({
    required this.item,
    required this.value,
    required this.onChanged,
  });

  final GeneratedFormSwitch item;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(item.label)),
        const SizedBox(width: 8),
        Switch(value: value, onChanged: item.disabled ? null : onChanged),
      ],
    );
  }
}

class _GeneratedFormState extends State<GeneratedForm> {
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic> values = {};
  late List<List<Widget>> formInputs;
  Key? initKey;
  int? _itemsHash;
  int _subFormGenerationCount = 0;
  final List<TextEditingController> _textControllers = [];

  void notifyFormChange({bool forceInvalid = false}) {
    final Map<String, dynamic> returnValues = values;
    var valid = true;
    for (int r = 0; r < formInputs.length; r++) {
      for (int i = 0; i < formInputs[r].length; i++) {
        if (formInputs[r][i] is TextFormField) {
          valid = valid && validateTextField(formInputs[r][i] as TextFormField);
        }
      }
    }
    if (forceInvalid) {
      valid = false;
    }
    widget.onValueChanges(returnValues, valid, false);
  }

  Widget _initTextField(GeneratedFormTextField formItem) {
    final formFieldKey = GlobalKey<FormFieldState>();
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
          decoration: InputDecoration(
            labelText: formItem.label + (formItem.required ? ' *' : ''),
            hintText: formItem.hint,
            filled: widget.tileMode ? false : null,
            border: widget.tileMode ? InputBorder.none : null,
            enabledBorder: widget.tileMode ? InputBorder.none : null,
            focusedBorder: widget.tileMode ? InputBorder.none : null,
            suffixIcon: formItem.helpUrl != null
                ? IconButton(
                    icon: const Icon(Icons.open_in_new),
                    tooltip: tr('about'),
                    onPressed: () => unawaited(
                      launchUrlString(
                        formItem.helpUrl!,
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  )
                : formItem.belowWidgets.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.help_outline),
                    tooltip: tr('about'),
                    onPressed: () => showHelpDialog(
                      context,
                      title: formItem.label,
                      content: formItem.belowWidgets as List<Widget>,
                    ),
                  )
                : null,
          ),
          minLines: formItem.max <= 1 ? null : formItem.max,
          maxLines: formItem.max <= 1 ? 1 : formItem.max,
          validator: (value) {
            if (formItem.required && (value == null || value.trim().isEmpty)) {
              return '${formItem.label} ${tr('requiredInBrackets')}';
            }
            for (var validator in formItem.additionalValidators) {
              final String? result = validator(value);
              if (result != null) {
                return result;
              }
            }
            return null;
          },
        );
        if (context.read<SettingsProvider>().isTV) {
          return _TVTextFieldFocus(textFocusNode: focusNode, child: textField);
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
      decoration: InputDecoration(
        labelText: formItem.label,
        filled: widget.tileMode ? false : null,
        border: widget.tileMode ? InputBorder.none : null,
        enabledBorder: widget.tileMode ? InputBorder.none : null,
        focusedBorder: widget.tileMode ? InputBorder.none : null,
      ),
      initialValue: values[formItem.key],
      items: formItem.opts!.map((e2) {
        final enabled = formItem.disabledOptKeys?.contains(e2.key) != true;
        return DropdownMenuItem(
          value: e2.key,
          enabled: enabled,
          child: Opacity(opacity: enabled ? 1 : 0.5, child: Text(e2.value)),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          values[formItem.key] = value ?? formItem.opts!.first.key;
          notifyFormChange();
        });
      },
    );
  }

  void _initSubForm(GeneratedFormSubForm formItem) {
    values[formItem.key] = [];
    for (Map<String, dynamic> v in ((formItem.value ?? []) as List<dynamic>)) {
      final fullDefaults = getDefaultValuesFromFormItems(formItem.items);
      for (var element in v.entries) {
        fullDefaults[element.key] = element.value;
      }
      values[formItem.key].add(fullDefaults);
    }
  }

  int _computeItemsHash(List<List<GeneratedFormItem>> items) {
    return Object.hashAll(
      items.expand((row) => row.map((e) => Object.hash(e.key, e.value))),
    );
  }

  void _initFormData() {
    initKey = widget.key;
    _itemsHash = _computeItemsHash(widget.items);
    for (final c in _textControllers) {
      c.dispose();
    }
    _textControllers.clear();
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
      notifyFormChange();
    });
  }

  @override
  void didUpdateWidget(covariant GeneratedForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.key != initKey ||
        _computeItemsHash(widget.items) != _itemsHash) {
      _initFormData();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyFormChange();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _textControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _buildSubForm(GeneratedFormSubForm item, String fieldKey) {
    final List<Widget> subformColumn = [];
    final compact = item.items.length == 1 && item.items[0].length == 1;
    for (int i = 0; i < values[fieldKey].length; i++) {
      final internalFormKey = ValueKey(
        generateRandomNumber(
          values[fieldKey].length,
          seed2: i,
          seed3: _subFormGenerationCount,
        ),
      );
      subformColumn.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact) const SizedBox(height: 16),
            if (!compact)
              Text(
                '${item.label} (${i + 1})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            GeneratedForm(
              key: internalFormKey,
              items: cloneFormItems(item.items)
                  .map(
                    (x) => x.map((y) {
                      y.value = values[fieldKey]?[i]?[y.key];
                      y.key = '${y.key.toString()},$internalFormKey';
                      return y;
                    }).toList(),
                  )
                  .toList(),
              onValueChanges: (values, valid, isBuilding) {
                values = values.map(
                  (key, value) => MapEntry(key.split(',')[0], value),
                );
                if (valid) {
                  this.values[fieldKey]?[i] = values;
                }
                notifyFormChange(forceInvalid: !valid);
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: (values[fieldKey].length > 0)
                      ? () {
                          final temp = List.from(values[fieldKey]);
                          temp.removeAt(i);
                          values[fieldKey] = List.from(temp);
                          _subFormGenerationCount++;
                          notifyFormChange();
                        }
                      : null,
                  label: Text('${item.label} (${i + 1})'),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ],
        ),
      );
    }
    subformColumn.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 0, top: 8),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () {
                  values[fieldKey].add(
                    getDefaultValuesFromFormItems(item.items),
                  );
                  _subFormGenerationCount++;
                  notifyFormChange();
                },
                icon: const Icon(Icons.add),
                label: Text(item.label),
              ),
            ),
          ],
        ),
      ),
    );
    return Column(children: subformColumn);
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
          renderedInputs[r][e] = _FormSwitchRow(
            item: item,
            value: values[fieldKey] as bool,
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
          renderedInputs[r][e] = _buildSubForm(item, fieldKey);
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
      final colorScheme = Theme.of(context).colorScheme;
      final n = inputRowWidgets.length;
      final List<Widget> children = [];
      for (var r = 0; r < n; r++) {
        final EdgeInsets padding = isFieldRow(r)
            ? EdgeInsets.zero
            : (widget.items[r].isNotEmpty &&
                  widget.items[r][0] is GeneratedFormSwitch)
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 4)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
        children.add(
          Material(
            color: isFieldRow(r)
                ? colorScheme.surfaceContainerHighest
                : colorScheme.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            shape: positionalTileShape(isFirst: r == 0, isLast: r == n - 1),
            child: Padding(padding: padding, child: inputRowWidgets[r]),
          ),
        );
      }
      return Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 3,
          children: children,
        ),
      );
    }

    final List<Widget> children = [];
    for (var r = 0; r < inputRowWidgets.length; r++) {
      if (r > 0) {
        children.add(
          SizedBox(
            height: widget.items[r - 1][0] is GeneratedFormSwitch ? 16 : 28,
          ),
        );
      }
      children.add(inputRowWidgets[r]);
    }

    return Form(
      key: _formKey,
      child: Column(children: children),
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
            items: widget.items,
            onValueChanges: (values, valid, isBuilding) {
              if (isBuilding) {
                this.values = values;
                this.valid = valid;
              } else {
                setState(() {
                  this.values = values;
                  this.valid = valid;
                });
              }
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
