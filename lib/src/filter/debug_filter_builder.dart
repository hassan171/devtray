import 'package:flutter/material.dart';

import '../core/debug_overlay_theme.dart';
import 'debug_filter.dart';

/// A JQL-style condition builder — a row of `field op value ✕` pills, AND-ed,
/// that wrap to new lines when they run out of room.
///
/// Ported from hapster's `LogFilterBuilder` and made generic over the entry
/// type + themed with [DebugOverlayTheme], so any page can offer advanced
/// filtering over its own [FilterField]s.
class DebugFilterBuilder<T> extends StatelessWidget {
  final List<FilterCondition<T>> conditions;

  /// The fields a condition may target — drives the key dropdown + value
  /// pickers.
  final Map<String, FilterField<T>> fields;

  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  /// Called whenever any condition's field/op/value changes.
  final VoidCallback onChanged;

  const DebugFilterBuilder({super.key, required this.conditions, required this.fields, required this.onAdd, required this.onRemove, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final keys = fields.keys.toList();

    return Align(
      alignment: Alignment.topLeft,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.start,
        children: [
          for (var i = 0; i < conditions.length; i++) ...[
            if (i > 0)
              Container(
                height: 34,
                width: 34,
                alignment: Alignment.center,
                child: Text(
                  'AND',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: t.textMuted),
                ),
              ),
            _ConditionPill<T>(condition: conditions[i], fieldKeys: keys, fields: fields, onChanged: onChanged, onRemove: () => onRemove(i)),
          ],
          _AddConditionButton(onTap: onAdd),
        ],
      ),
    );
  }
}

class _AddConditionButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddConditionButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: t.accent),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 16, color: t.accent),
            const SizedBox(width: 4),
            Text(
              'Add filter',
              style: TextStyle(fontSize: 12, color: t.accent, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single self-sizing condition pill: `field op value ✕`.
class _ConditionPill<T> extends StatelessWidget {
  final FilterCondition<T> condition;
  final List<String> fieldKeys;
  final Map<String, FilterField<T>> fields;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _ConditionPill({required this.condition, required this.fieldKeys, required this.fields, required this.onChanged, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: t.surface.withValues(alpha: 0.6),
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.only(left: 8, right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DropdownBox<String>(
            value: condition.field.isEmpty ? null : condition.field,
            hint: 'field',
            items: fieldKeys,
            labelOf: (k) => k,
            onChanged: (k) {
              condition.field = k ?? '';
              condition.value = ''; // reset — suggestions differ per field
              onChanged();
            },
          ),
          const SizedBox(width: 4),
          _DropdownBox<FilterOp>(
            value: condition.op,
            hint: 'op',
            items: FilterOp.values,
            labelOf: (o) => o.label,
            onChanged: (o) {
              condition.op = o ?? FilterOp.equals;
              onChanged();
            },
          ),
          const SizedBox(width: 4),
          _ValueInput<T>(condition: condition, fields: fields, onChanged: onChanged),
          IconButton(
            tooltip: 'Remove',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(Icons.close, size: 14, color: t.textMuted),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Enum-valued fields with a single-value op get a picker; everything else
/// (and multi-value/regex/contains) gets a text field.
class _ValueInput<T> extends StatelessWidget {
  final FilterCondition<T> condition;
  final Map<String, FilterField<T>> fields;
  final VoidCallback onChanged;

  const _ValueInput({required this.condition, required this.fields, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final suggestions = fields[condition.field]?.suggestions ?? const [];
    final usePicker =
        suggestions.isNotEmpty &&
        !condition.op.isMultiValue &&
        condition.op != FilterOp.regex &&
        condition.op != FilterOp.contains &&
        condition.op != FilterOp.notContains;

    if (usePicker) {
      return _DropdownBox<String>(
        value: suggestions.contains(condition.value) ? condition.value : null,
        hint: 'value',
        items: suggestions,
        labelOf: (v) => v,
        onChanged: (v) {
          condition.value = v ?? '';
          onChanged();
        },
      );
    }

    return _ValueField(
      // Rebuild the field (and its controller) when field/op change so the hint
      // and initial text stay in sync.
      key: ValueKey('${condition.field}|${condition.op}'),
      initial: condition.value,
      hint: condition.op.isMultiValue
          ? 'a, b, c'
          : condition.op == FilterOp.regex
          ? 'regex'
          : 'value',
      onChanged: (v) {
        condition.value = v;
        onChanged();
      },
    );
  }
}

class _ValueField extends StatefulWidget {
  final String initial;
  final String hint;
  final ValueChanged<String> onChanged;

  const _ValueField({super.key, required this.initial, required this.hint, required this.onChanged});

  @override
  State<_ValueField> createState() => _ValueFieldState();
}

class _ValueFieldState extends State<_ValueField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    // TextFields want infinite width; cap it so the pill stays compact and the
    // Wrap can break to a new line.
    return SizedBox(
      height: 34,
      width: 130,
      child: TextField(
        controller: _controller,
        style: TextStyle(fontSize: 12, color: t.text),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(fontSize: 12, color: t.textMuted),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _DropdownBox<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  const _DropdownBox({required this.value, required this.hint, required this.items, required this.labelOf, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    // Content-sized (no isExpanded) so the enclosing pill hugs its controls and
    // the Wrap can pack pills side by side. selectedItemBuilder caps the closed
    // button's width while the open menu still shows full, untruncated labels.
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isDense: true,
        dropdownColor: t.surface,
        hint: Text(hint, style: TextStyle(fontSize: 12, color: t.textMuted)),
        icon: Icon(Icons.arrow_drop_down, size: 18, color: t.textMuted),
        style: TextStyle(fontSize: 12, color: t.text),
        selectedItemBuilder: (context) => [
          for (final item in items)
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  labelOf(item),
                  style: TextStyle(fontSize: 12, color: t.text),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
        ],
        items: [
          for (final item in items)
            DropdownMenuItem<T>(
              value: item,
              child: Text(
                labelOf(item),
                style: TextStyle(fontSize: 12, color: t.text),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
