import 'package:material_ui/material_ui.dart';

import '../../models/core_models.dart';
import '../../theme/app_theme.dart';

class DynamicSchemaForm extends StatelessWidget {
  const DynamicSchemaForm({
    super.key,
    required this.schema,
    required this.values,
    required this.onChanged,
  });

  final PlatformSchema schema;
  final Map<String, dynamic> values;
  final ValueChanged<Map<String, dynamic>> onChanged;

  void _updateKey(String key, dynamic val) {
    final next = Map<String, dynamic>.from(values);
    next[key] = val;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: schema.fields.map((field) {
        final cur = values.containsKey(field.key)
            ? values[field.key]
            : field.defaultValue;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildField(context, field, cur),
        );
      }).toList(),
    );
  }

  Widget _buildField(
    BuildContext context,
    ParamFieldDef field,
    dynamic currentValue,
  ) {
    switch (field.fieldType) {
      case ParamFieldType.slider:
        return _SliderRow(
          field: field,
          value:
              _asDouble(currentValue) ??
              _asDouble(field.defaultValue) ??
              field.min ??
              1.0,
          onChanged: (v) => _updateKey(field.key, v),
        );
      case ParamFieldType.stepper:
        return _StepperRow(
          field: field,
          value:
              _asDouble(currentValue)?.toInt() ??
              _asDouble(field.defaultValue)?.toInt() ??
              (field.min?.toInt() ?? 1),
          onChanged: (v) => _updateKey(field.key, v),
        );
      case ParamFieldType.select:
        final strVal = '$currentValue';
        final opts = {strVal, ...field.options}.toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FieldHeader(field: field),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              key: ValueKey('${schema.id}_${field.key}_$strVal'),
              initialValue: strVal,
              isExpanded: true,
              items: opts
                  .map(
                    (o) => DropdownMenuItem(
                      value: o,
                      child: Text(o, style: const TextStyle(fontSize: 13)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) _updateKey(field.key, v);
              },
            ),
          ],
        );
      case ParamFieldType.toggle:
        final b = currentValue == true;
        return Material(
          color: StyleLoomTheme.surfaceHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: StyleLoomTheme.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            title: Text(field.label, style: const TextStyle(fontSize: 13)),
            subtitle: field.hint != null
                ? Text(
                    field.hint!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: StyleLoomTheme.textSecondary,
                    ),
                  )
                : null,
            value: b,
            onChanged: (v) => _updateKey(field.key, v),
          ),
        );
      case ParamFieldType.resolution:
        final resStr = '$currentValue';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FieldHeader(field: field),
            const SizedBox(height: 6),
            if (field.resolutionPresets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: field.resolutionPresets.map((preset) {
                    return ChoiceChip(
                      label: Text(preset, style: const TextStyle(fontSize: 11)),
                      selected: resStr == preset,
                      onSelected: (_) => _updateKey(field.key, preset),
                    );
                  }).toList(),
                ),
              ),
            _ParamTextField(
              key: ValueKey('${schema.id}_${field.key}_resolution'),
              value: resStr,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(hintText: '例如 832x1216'),
              onChanged: (v) => _updateKey(field.key, v),
            ),
          ],
        );
      case ParamFieldType.text:
        final txt = currentValue?.toString() ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FieldHeader(field: field),
            const SizedBox(height: 6),
            _ParamTextField(
              key: ValueKey('${schema.id}_${field.key}_text'),
              value: txt,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(hintText: field.hint ?? '输入备注或触发词…'),
              onChanged: (v) => _updateKey(field.key, v),
            ),
          ],
        );
      case ParamFieldType.loraList:
        final rawList = currentValue is List ? currentValue : [];
        final loras = rawList
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        return _LoraListEditor(
          field: field,
          loras: loras,
          onChanged: (next) => _updateKey(field.key, next),
        );
    }
  }
}

double? _asDouble(dynamic value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  return number != null && number.isFinite ? number : null;
}

class _ParamTextField extends StatefulWidget {
  const _ParamTextField({
    super.key,
    required this.value,
    required this.style,
    required this.decoration,
    required this.onChanged,
  });

  final String value;
  final TextStyle style;
  final InputDecoration decoration;
  final ValueChanged<String> onChanged;

  @override
  State<_ParamTextField> createState() => _ParamTextFieldState();
}

class _ParamTextFieldState extends State<_ParamTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(covariant _ParamTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    style: widget.style,
    decoration: widget.decoration,
    onChanged: widget.onChanged,
  );
}

class _FieldHeader extends StatelessWidget {
  const _FieldHeader({required this.field, this.badge});
  final ParamFieldDef field;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            field.label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: StyleLoomTheme.textPrimary,
            ),
          ),
        ),
        ?badge,
      ],
    );
  }
}

Widget? _buildRecommendBadge(ParamFieldDef field, double val) {
  final rMin = field.recommendedMin;
  final rMax = field.recommendedMax;
  if (rMin == null || rMax == null) return null;
  final inRange = val >= rMin - 0.001 && val <= rMax + 0.001;
  final label = '推荐 ${_fmtNum(rMin)}–${_fmtNum(rMax)}';
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: (inRange ? StyleLoomTheme.teal : StyleLoomTheme.amber).withValues(
        alpha: 0.16,
      ),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      inRange ? label : '超出$label',
      style: TextStyle(
        fontSize: 10,
        color: inRange ? StyleLoomTheme.teal : StyleLoomTheme.amber,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

String _fmtNum(double v) {
  if ((v - v.roundToDouble()).abs() < 0.001) return v.round().toString();
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.field,
    required this.value,
    required this.onChanged,
  });

  final ParamFieldDef field;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final min = field.min ?? 0.0;
    final max = (field.max ?? 10.0) < min ? min : (field.max ?? 10.0);
    final step = (field.step ?? 0.1) > 0 ? (field.step ?? 0.1) : 0.1;
    final clamped = value.clamp(min, max);
    final divisions = ((max - min) / step).round().clamp(1, 500);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      decoration: BoxDecoration(
        color: StyleLoomTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: StyleLoomTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldHeader(
            field: field,
            badge: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_buildRecommendBadge(field, clamped) case final b?) ...[
                  b,
                  const SizedBox(width: 6),
                ],
                Text(
                  _fmtNum(clamped),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: StyleLoomTheme.accent,
                  ),
                ),
              ],
            ),
          ),
          Slider(
            value: clamped,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: min == max
                ? null
                : (v) {
                    final snapped = (min + ((v - min) / step).round() * step)
                        .clamp(min, max);
                    onChanged(double.parse(snapped.toStringAsFixed(3)));
                  },
          ),
          if (field.hint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                field.hint!,
                style: const TextStyle(
                  fontSize: 11,
                  color: StyleLoomTheme.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.field,
    required this.value,
    required this.onChanged,
  });

  final ParamFieldDef field;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final min = (field.min ?? 1).toInt();
    final requestedMax = (field.max ?? 100).toInt();
    final max = requestedMax < min ? min : requestedMax;
    final clamped = value.clamp(min, max);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: StyleLoomTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: StyleLoomTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (field.hint != null)
                      Text(
                        field.hint!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: StyleLoomTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (_buildRecommendBadge(field, clamped.toDouble())
                  case final b?) ...[
                b,
                const SizedBox(width: 8),
              ],
              IconButton(
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                visualDensity: VisualDensity.compact,
                onPressed: clamped > min ? () => onChanged(clamped - 1) : null,
              ),
              SizedBox(
                width: 34,
                child: Text(
                  '$clamped',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                visualDensity: VisualDensity.compact,
                onPressed: clamped < max ? () => onChanged(clamped + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoraListEditor extends StatelessWidget {
  const _LoraListEditor({
    required this.field,
    required this.loras,
    required this.onChanged,
  });

  final ParamFieldDef field;
  final List<Map<String, dynamic>> loras;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: StyleLoomTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: StyleLoomTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  field.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  onChanged([
                    ...loras,
                    {'name': '', 'weight': 0.85},
                  ]);
                },
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('添加 LoRA', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (field.hint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                field.hint!,
                style: const TextStyle(
                  fontSize: 11,
                  color: StyleLoomTheme.textSecondary,
                ),
              ),
            ),
          if (loras.isEmpty)
            const Text(
              '未挂载 LoRA',
              style: TextStyle(
                fontSize: 12,
                color: StyleLoomTheme.textSecondary,
              ),
            ),
          ...List.generate(loras.length, (i) {
            final item = loras[i];
            final w = (_asDouble(item['weight']) ?? 1.0).clamp(-2.0, 2.0);
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _ParamTextField(
                      key: ValueKey('lora_${field.key}_$i'),
                      value: item['name']?.toString() ?? '',
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(hintText: 'LoRA 名称'),
                      onChanged: (v) {
                        final next = loras
                            .map((m) => Map<String, dynamic>.from(m))
                            .toList();
                        next[i]['name'] = v;
                        onChanged(next);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    child: Slider(
                      value: w,
                      min: -2.0,
                      max: 2.0,
                      divisions: 80,
                      onChanged: (nv) {
                        final next = loras
                            .map((m) => Map<String, dynamic>.from(m))
                            .toList();
                        next[i]['weight'] = double.parse(nv.toStringAsFixed(2));
                        onChanged(next);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      w.toStringAsFixed(2),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 17),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      final next = loras
                          .map((m) => Map<String, dynamic>.from(m))
                          .toList();
                      next.removeAt(i);
                      onChanged(next);
                    },
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
