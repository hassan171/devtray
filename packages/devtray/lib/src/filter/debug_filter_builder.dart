import 'package:flutter/material.dart';

import '../core/devtray_theme.dart';
import '../core/debug_text_styles.dart';
import 'debug_filter.dart';

/// A JQL-style condition builder — a row of `field op value ✕` pills, AND-ed,
/// that wrap to new lines when they run out of room.
///
/// Ported from hapster's `LogFilterBuilder` and made generic over the entry
/// type + themed with [DevtrayTheme], so any page can offer advanced
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
    final t = DevtrayTheme.of(context);
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
              // Conditions are AND-ed. Quiet, because it's a fixed truth about
              // every pair — not something to read on each pass.
              Container(
                height: 34,
                width: 34,
                alignment: Alignment.center,
                child: Text('and', style: TextStyle(fontSize: 10, color: t.textMuted.withValues(alpha: 0.7))),
              ),
            _ConditionPill<T>(condition: conditions[i], fieldKeys: keys, fields: fields, onChanged: onChanged, onRemove: () => onRemove(i)),
          ],
          _AddConditionButton(onTap: onAdd, isFirst: conditions.isEmpty),
        ],
      ),
    );
  }
}

class _AddConditionButton extends StatelessWidget {
  final VoidCallback onTap;

  /// True when no conditions exist yet — the button is then the *only* thing on
  /// the row, so it recedes rather than sitting there as a loud outlined pill
  /// above an unfiltered list.
  final bool isFirst;

  const _AddConditionButton({required this.onTap, required this.isFirst});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isFirst ? Colors.transparent : t.accent.withValues(alpha: 0.10),
          border: Border.all(color: isFirst ? t.border.withValues(alpha: 0.8) : Colors.transparent),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 14, color: isFirst ? t.textMuted : t.accent),
            const SizedBox(width: 4),
            Text(
              'Add filter',
              style: TextStyle(fontSize: 11, color: isFirst ? t.textMuted : t.accent, fontWeight: FontWeight.w500),
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
    final t = DevtrayTheme.of(context);

    // A pill is `mainAxisSize.min` inside a Wrap, so it takes its intrinsic
    // width — and a Wrap can't shrink a child that asks for too much. Two
    // dropdowns plus a value field exceed a phone's width, which overflowed the
    // Row. Capping against the real constraints lets the value field give way
    // instead (see _ValueField), so the pill always fits.
    return LayoutBuilder(
      builder: (context, constraints) {
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
          child: Container(
            height: 32,
            decoration: BoxDecoration(
              // An active condition is *changing what you see*, so it reads as
              // armed rather than as another piece of neutral chrome.
              color: t.accent.withValues(alpha: 0.08),
              border: Border.all(color: t.accent.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.only(left: 8, right: 2),
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
                // Flexible, so the value is what yields when space runs out —
                // the field and op dropdowns are short and fixed, and losing
                // *which field* you filtered on would be worse.
                Flexible(
                  child: _ValueInput<T>(condition: condition, fields: fields, onChanged: onChanged),
                ),
                IconButton(
                  tooltip: 'Remove',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                  icon: Icon(Icons.close, size: 14, color: t.textMuted),
                  onPressed: onRemove,
                ),
              ],
            ),
          ),
        );
      },
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
    final t = DevtrayTheme.of(context);

    // A TextField wants infinite width, so it needs a cap or the pill would
    // stretch forever. A *max* rather than a fixed width: the enclosing
    // Flexible shrinks this below 130 on a narrow screen instead of overflowing.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 130, minWidth: 60, maxHeight: 32, minHeight: 32),
      child: TextField(
        controller: _controller,
        cursorColor: t.accent,
        cursorWidth: 1.5,
        // A filter value is matched against captured data — mono, like the data.
        style: DebugTextStyles.debugMono(color: t.text, fontSize: 12),
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
    final t = DevtrayTheme.of(context);

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
