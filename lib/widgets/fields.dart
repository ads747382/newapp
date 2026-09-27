import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.error,
    this.hint,
    this.helper,
    this.keyboard,
    this.maxLines = 1,
    this.maxLength,
    this.required = false,
    this.obscure = false,
    this.enabled = true,
    this.capitalization = TextCapitalization.none,
    this.formatters,
    this.onChanged,
    this.suffix,
    this.autofill,
  });

  final TextEditingController controller;
  final String label;
  final String? error;
  final String? hint;
  final String? helper;
  final TextInputType? keyboard;
  final int maxLines;
  final int? maxLength;
  final bool required;
  final bool obscure;
  final bool enabled;
  final TextCapitalization capitalization;
  final List<TextInputFormatter>? formatters;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  final Iterable<String>? autofill;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: obscure ? 1 : maxLines,
        minLines: 1,
        maxLength: maxLength,
        obscureText: obscure,
        enabled: enabled,
        textCapitalization: capitalization,
        inputFormatters: formatters,
        onChanged: onChanged,
        autofillHints: autofill,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: hint,
          helperText: helper,
          helperMaxLines: 3,
          errorText: error,
          errorMaxLines: 3,
          counterText: '',
          suffixIcon: suffix,
        ),
      ),
    );
  }
}

class PasswordInput extends StatefulWidget {
  const PasswordInput({super.key, required this.controller, required this.label, this.error, this.helper, this.autofill});

  final TextEditingController controller;
  final String label;
  final String? error;
  final String? helper;
  final Iterable<String>? autofill;

  @override
  State<PasswordInput> createState() => _PasswordInputState();
}

class _PasswordInputState extends State<PasswordInput> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: widget.controller,
      label: widget.label,
      error: widget.error,
      helper: widget.helper,
      obscure: _hidden,
      autofill: widget.autofill,
      suffix: IconButton(icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hidden = !_hidden)),
    );
  }
}

class Choice {
  const Choice(this.value, this.label);

  final String value;
  final String label;
}

class ChoiceInput extends StatelessWidget {
  const ChoiceInput({
    super.key,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.error,
    this.required = false,
    this.allowEmpty = false,
    this.helper,
  });

  final String label;
  final String? value;
  final List<Choice> choices;
  final ValueChanged<String?> onChanged;
  final String? error;
  final bool required;
  final bool allowEmpty;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final items = [
      if (allowEmpty) const DropdownMenuItem<String>(value: '', child: Text('—')),
      for (final c in choices)
        DropdownMenuItem<String>(
          value: c.value,
          child: Text(c.label, overflow: TextOverflow.ellipsis),
        ),
    ];
    final current = (value != null && items.any((i) => i.value == value)) ? value : (allowEmpty ? '' : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$current-${choices.length}'),
        initialValue: current,
        isExpanded: true,
        items: items,
        onChanged: (v) => onChanged(v == '' ? null : v),
        decoration: InputDecoration(labelText: required ? '$label *' : label, errorText: error, helperText: helper, helperMaxLines: 3),
      ),
    );
  }
}

/// Date picker field storing yyyy-MM-dd.
class DateInput extends StatelessWidget {
  const DateInput({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.error,
    this.required = false,
    this.first,
    this.last,
    this.clearable = true,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? error;
  final bool required;
  final DateTime? first;
  final DateTime? last;
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    final current = DateTime.tryParse(value ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: current ?? DateTime.now(),
            firstDate: first ?? DateTime(1950),
            lastDate: last ?? DateTime(DateTime.now().year + 5),
          );
          if (picked != null) onChanged(isoDate(picked));
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: required ? '$label *' : label,
            errorText: error,
            suffixIcon: value != null && value!.isNotEmpty && clearable && !required
                ? IconButton(icon: const Icon(Icons.clear), onPressed: () => onChanged(null))
                : const Icon(Icons.calendar_today_outlined, size: 20),
          ),
          child: Text(current == null ? 'Select date' : fmtDate(value)),
        ),
      ),
    );
  }
}

/// Month picker storing yyyy-MM.
class MonthInput extends StatelessWidget {
  const MonthInput({super.key, required this.label, required this.value, required this.onChanged, this.error});

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = [for (var i = -36; i <= 3; i++) DateTime(now.year, now.month + i, 1)].reversed.toList();
    return ChoiceInput(
      label: label,
      value: value,
      error: error,
      required: true,
      choices: [for (final m in months) Choice(isoMonth(m), fmtMonth(isoMonth(m)))],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class AmountInput extends StatelessWidget {
  const AmountInput({super.key, required this.controller, required this.label, this.error, this.required = false, this.helper});

  final TextEditingController controller;
  final String label;
  final String? error;
  final bool required;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: label,
      error: error,
      helper: helper,
      required: required,
      keyboard: const TextInputType.numberWithOptions(decimal: true),
      formatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,10}(\.\d{0,2})?'))],
      suffix: Padding(padding: const EdgeInsets.all(14), child: Text(currencySymbol)),
    );
  }
}

/// A heading between groups of fields.
class FormHeading extends StatelessWidget {
  const FormHeading(this.text, {super.key, this.sub});

  final String text;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
          ),
          if (sub != null) Text(sub!, style: t.bodySmall),
        ],
      ),
    );
  }
}
