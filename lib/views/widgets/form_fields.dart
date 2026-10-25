import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';

/// Label above a field, optional helper text below (as in the designs).
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child, this.helper, this.helperIcon});
  final String label;
  final Widget child;
  final String? helper;
  final IconData? helperIcon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        child,
        if (helper != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (helperIcon != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(helperIcon, size: 13, color: AppColors.textMuted),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(child: Text(helper!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
            ],
          ),
        ],
      ],
    );
  }
}

/// TextFormField with the app's defaults. Enter submits (single-line).
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.initialValue,
    this.hint,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.obscure = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.keyboardType,
    this.suffix,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.numeric = false,
    this.textAlign = TextAlign.start,
    this.autofillHints,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;
  final bool obscure;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final bool numeric;
  final TextAlign textAlign;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final multiline = maxLines > 1;
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: multiline || onSubmitted == null ? null : (_) => onSubmitted!(),
      obscureText: obscure,
      maxLines: obscure ? 1 : maxLines,
      minLines: minLines,
      enabled: enabled,
      readOnly: readOnly,
      autofocus: autofocus,
      textAlign: textAlign,
      autofillHints: autofillHints,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : (multiline ? TextInputType.multiline : keyboardType),
      textInputAction: multiline ? TextInputAction.newline : TextInputAction.done,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      // hard cap so users can't paste megabytes; the validator explains limits
      inputFormatters: [
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength! + 1),
        if (numeric) FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        suffixIcon: suffix,
        fillColor: enabled && !readOnly ? Colors.white : AppColors.background,
      ),
    );
  }
}

/// Styled dropdown that participates in Form validation.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.labelOf,
    this.hint,
    this.validator,
    this.errorText,
    this.dense = false,
  });

  final T? value;
  final List<T> items;
  final ValueChanged<T?>? onChanged;
  final String Function(T) labelOf;
  final String? hint;
  final FormFieldValidator<T>? validator;
  final String? errorText;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      // ignore: deprecated_member_use
      value: items.contains(value) ? value : null,
      isExpanded: true,
      validator: validator,
      onChanged: onChanged,
      icon: const Icon(Icons.keyboard_arrow_down, size: 18),
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(8),
      decoration: InputDecoration(
        hintText: hint,
        errorText: errorText,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 9 : 12),
        fillColor: onChanged == null ? AppColors.background : Colors.white,
      ),
      items: [
        for (final i in items)
          DropdownMenuItem<T>(value: i, child: Text(labelOf(i), overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// Looks like a text field; opens a date picker.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.firstDate,
    this.enabled = true,
    this.dense = false,
    this.placeholder = 'dd mmm yyyy',
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? errorText;
  final DateTime? firstDate;
  final bool enabled;
  final bool dense;
  final String placeholder;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final first = firstDate ?? DateTime(now.year, now.month, now.day);
    final initial = value != null && !value!.isBefore(first) ? value! : first;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          errorText: errorText,
          enabled: enabled,
          fillColor: enabled ? Colors.white : AppColors.background,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 9 : 12),
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
          suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 20),
        ),
        child: Text(
          value == null ? placeholder : Fmt.date(value),
          style: TextStyle(fontSize: 14, color: value == null ? AppColors.textMuted : AppColors.textPrimary),
        ),
      ),
    );
  }
}

/// Search box used above tables.
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.hint, required this.onChanged, this.initialValue = '', this.width = 320});
  final String hint;
  final ValueChanged<String> onChanged;
  final String initialValue;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextFormField(
        initialValue: initialValue,
        onChanged: onChanged,
        inputFormatters: [LengthLimitingTextInputFormatter(100)],
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textMuted),
          prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 20),
        ),
      ),
    );
  }
}

/// Makes Enter (and Ctrl+Enter inside multiline fields) trigger [onSubmit].
class SubmitOnEnter extends StatelessWidget {
  const SubmitOnEnter({super.key, required this.onSubmit, required this.child});
  final VoidCallback onSubmit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): onSubmit,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true): onSubmit,
      },
      child: child,
    );
  }
}
