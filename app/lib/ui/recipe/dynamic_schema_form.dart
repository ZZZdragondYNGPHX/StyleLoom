import 'package:flutter/services.dart' show LogicalKeyboardKey;
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
          padding: const EdgeInsets.only(bottom: 12),
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
    final c = EditorialColors.of(context);
    switch (field.fieldType) {
      case ParamFieldType.slider:
        return _EditorialSafeBandSlider(
          field: field,
          editable: schema.platform == 'NovelAI' &&
              (field.key == 'cfg' || field.key == 'cfg_rescale'),
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
        return _ParamBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FieldHeader(field: field),
              const SizedBox(height: 8),
              if (opts.length <= 5)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: opts.map((opt) {
                    final active = strVal == opt;
                    return InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _updateKey(field.key, opt),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: active ? c.accent : c.surface,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          opt,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: active ? const Color(0xFFFFFEFA) : c.muted,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                )
              else
                DropdownButtonFormField<String>(
                  key: ValueKey('${schema.id}_${field.key}_$strVal'),
                  initialValue: strVal,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: c.surface,
                  ),
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
          ),
        );
      case ParamFieldType.toggle:
        final b = currentValue == true;
        return _ParamBox(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _updateKey(field.key, !b),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        field.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                      if (field.hint != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          field.hint!,
                          style: TextStyle(fontSize: 11, color: c.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _EditorialSwitch(
                  value: b,
                  onChanged: (v) => _updateKey(field.key, v),
                ),
              ],
            ),
          ),
        );
      case ParamFieldType.resolution:
        final resStr = '$currentValue';
        return _ParamBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FieldHeader(field: field),
              const SizedBox(height: 8),
              if (field.resolutionPresets.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: field.resolutionPresets.map((preset) {
                      final active = resStr == preset;
                      return InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => _updateKey(field.key, preset),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: active ? c.accent : c.surface,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            preset,
                            style: StyleLoomTheme.monoStyle(
                              fontSize: 11.5,
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: active
                                  ? const Color(0xFFFFFEFA)
                                  : c.muted,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              _ParamTextField(
                key: ValueKey('${schema.id}_${field.key}_resolution'),
                value: resStr,
                style: StyleLoomTheme.monoStyle(fontSize: 13, color: c.ink),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: c.surface,
                  hintText: '例如 832x1216',
                ),
                onChanged: (v) => _updateKey(field.key, v),
              ),
            ],
          ),
        );
      case ParamFieldType.text:
        final txt = currentValue?.toString() ?? '';
        return _ParamBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FieldHeader(field: field),
              const SizedBox(height: 8),
              _ParamTextField(
                key: ValueKey('${schema.id}_${field.key}_text'),
                value: txt,
                style: TextStyle(fontSize: 13, color: c.ink),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: c.surface,
                  hintText: field.hint ?? '输入备注或触发词…',
                ),
                onChanged: (v) => _updateKey(field.key, v),
              ),
            ],
          ),
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

class _ParamBox extends StatelessWidget {
  const _ParamBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: c.trough,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class _EditorialSwitch extends StatelessWidget {
  const _EditorialSwitch({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 42,
        height: 24,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? c.celadon : c.troughDeep,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: c.surface,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: c.shadowColor.withValues(alpha: 0.18),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
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
    final c = EditorialColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            field.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
        ),
        ?badge,
      ],
    );
  }
}

Widget? _buildRecommendBadge(
  BuildContext context,
  ParamFieldDef field,
  double val,
) {
  final rMin = field.recommendedMin;
  final rMax = field.recommendedMax;
  if (rMin == null || rMax == null) return null;
  final c = EditorialColors.of(context);
  final inRange = val >= rMin - 0.001 && val <= rMax + 0.001;
  final label = '推荐 ${_fmtNum(rMin)}–${_fmtNum(rMax)}';
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: inRange ? c.celadonSoft : c.warnSoft,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      inRange ? label : '超出$label',
      style: TextStyle(
        fontSize: 10.5,
        color: inRange ? c.celadon : c.warn,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

String _fmtNum(double v) {
  if ((v - v.roundToDouble()).abs() < 0.001) return v.round().toString();
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

class _EditorialSafeBandSlider extends StatelessWidget {
  const _EditorialSafeBandSlider({
    required this.field,
    required this.editable,
    required this.value,
    required this.onChanged,
  });

  final ParamFieldDef field;
  final bool editable;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    final min = field.min ?? 0.0;
    final max = (field.max ?? 10.0) < min ? min : (field.max ?? 10.0);
    final step = (field.step ?? 0.1) > 0 ? (field.step ?? 0.1) : 0.1;
    final clamped = value.clamp(min, max);
    final divisions = ((max - min) / step).round().clamp(1, 500);
    final span = (max - min) <= 0 ? 1.0 : (max - min);
    final rMin = field.recommendedMin;
    final rMax = field.recommendedMax;
    final hasBand = rMin != null && rMax != null && max > min;
    final bandLeft = hasBand
        ? ((rMin.clamp(min, max) - min) / span).clamp(0.0, 1.0)
        : 0.0;
    final bandRight = hasBand
        ? ((rMax.clamp(min, max) - min) / span).clamp(0.0, 1.0)
        : 0.0;
    final inRange = !hasBand || (clamped >= rMin - 0.001 && clamped <= rMax + 0.001);
    final valueStyle = StyleLoomTheme.monoStyle(
      fontWeight: FontWeight.w700,
      fontSize: 13.5,
      color: inRange ? c.ink : c.warn,
    );

    return _ParamBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldHeader(
            field: field,
            badge: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_buildRecommendBadge(context, field, clamped)
                    case final b?) ...[
                  b,
                  const SizedBox(width: 8),
                ],
                if (editable)
                  _GuidanceInput(
                    key: ValueKey(field.key),
                    field: field,
                    value: clamped,
                    min: min,
                    max: max,
                    style: valueStyle,
                    onChanged: onChanged,
                  )
                else
                  Text(_fmtNum(clamped), style: valueStyle),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 底层槽与青瓷安全推荐区间高亮带
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: LayoutBuilder(
                    builder: (_, box) {
                      final w = box.maxWidth;
                      final leftPx = w * bandLeft;
                      final bandW = (w * (bandRight - bandLeft)).clamp(0.0, w);
                      return Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: c.troughDeep,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: hasBand
                            ? Stack(
                                children: [
                                  Positioned(
                                    left: leftPx,
                                    width: bandW,
                                    top: 0,
                                    bottom: 0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: c.celadon.withValues(
                                          alpha: c.isNight ? 0.52 : 0.42,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : null,
                      );
                    },
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    thumbColor: c.surface,
                    overlayColor: c.accentSoft,
                    thumbShape: _EditorialThumbShape(
                      ringColor: inRange ? c.accent : c.warn,
                      fillColor: c.surface,
                    ),
                  ),
                  child: Slider(
                    value: clamped,
                    min: min,
                    max: max,
                    divisions: divisions,
                    onChanged: min == max
                        ? null
                        : (v) {
                            final snapped =
                                (min + ((v - min) / step).round() * step).clamp(
                                  min,
                                  max,
                                );
                            onChanged(double.parse(snapped.toStringAsFixed(3)));
                          },
                  ),
                ),
              ],
            ),
          ),
          if (field.hint != null) ...[
            const SizedBox(height: 3),
            Text(
              field.hint!,
              style: TextStyle(fontSize: 11, color: c.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _GuidanceInput extends StatefulWidget {
  const _GuidanceInput({
    super.key,
    required this.field,
    required this.value,
    required this.min,
    required this.max,
    required this.style,
    required this.onChanged,
  });

  final ParamFieldDef field;
  final double value;
  final double min;
  final double max;
  final TextStyle style;
  final ValueChanged<double> onChanged;

  @override
  State<_GuidanceInput> createState() => _GuidanceInputState();
}

class _GuidanceInputState extends State<_GuidanceInput> {
  String _format(double value) => value.toString().replaceFirst(RegExp(r'\.0$'), '');

  late final _controller = TextEditingController(text: _format(widget.value));
  late final _focus = FocusNode()..addListener(_focusChanged);
  bool _dirty = false;

  double? get _draft {
    final value = _asDouble(_controller.text);
    return value != null && value >= widget.min && value <= widget.max ? value : null;
  }

  void _finish({bool cancel = false}) {
    if (!_dirty) return;
    final value = cancel ? widget.value : _draft ?? widget.value;
    setState(() => _dirty = false);
    _controller.text = _format(value);
    if (value != widget.value) widget.onChanged(value);
  }

  void _focusChanged() {
    if (!_focus.hasFocus) _finish();
  }

  @override
  void didUpdateWidget(covariant _GuidanceInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _dirty = false;
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 66,
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          _finish(cancel: true);
          _focus.unfocus();
        },
      },
      child: Semantics(
        label: widget.field.label,
        child: TextField(
          groupId: _focus,
          controller: _controller,
          focusNode: _focus,
          selectAllOnFocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          textAlign: TextAlign.center,
          style: widget.style,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: EditorialColors.of(context).surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            errorText: _dirty && _draft == null ? '${_fmtNum(widget.min)}–${_fmtNum(widget.max)}' : null,
          ),
          onChanged: (_) => setState(() => _dirty = true),
          onEditingComplete: () {
            if (_draft != null) {
              _finish();
              _focus.unfocus();
            }
          },
          onTapOutside: (_) {
            _finish();
            _focus.unfocus();
          },
        ),
      ),
    ),
  );
}

class _EditorialThumbShape extends SliderComponentShape {
  const _EditorialThumbShape({
    required this.ringColor,
    required this.fillColor,
  });

  final Color ringColor;
  final Color fillColor;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(16, 16);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(
      center + const Offset(0, 1.5),
      8,
      Paint()..color = Colors.black.withValues(alpha: 0.16),
    );
    canvas.drawCircle(center, 7.5, Paint()..color = fillColor);
    canvas.drawCircle(
      center,
      7.5,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
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
    final c = EditorialColors.of(context);
    final min = (field.min ?? 1).toInt();
    final requestedMax = (field.max ?? 100).toInt();
    final max = requestedMax < min ? min : requestedMax;
    final clamped = value.clamp(min, max);

    return _ParamBox(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  field.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                if (field.hint != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    field.hint!,
                    style: TextStyle(fontSize: 11, color: c.muted),
                  ),
                ],
              ],
            ),
          ),
          if (_buildRecommendBadge(context, field, clamped.toDouble())
              case final b?) ...[
            b,
            const SizedBox(width: 8),
          ],
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(999),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_rounded, size: 17),
                  visualDensity: VisualDensity.compact,
                  onPressed: clamped > min ? () => onChanged(clamped - 1) : null,
                ),
                SizedBox(
                  width: 30,
                  child: Text(
                    '$clamped',
                    textAlign: TextAlign.center,
                    style: StyleLoomTheme.monoStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: c.ink,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 17),
                  visualDensity: VisualDensity.compact,
                  onPressed: clamped < max ? () => onChanged(clamped + 1) : null,
                ),
              ],
            ),
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
    final c = EditorialColors.of(context);
    return _ParamBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  field.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  onChanged([
                    ...loras,
                    {'name': '', 'weight': 0.85},
                  ]);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 14, color: c.accent),
                      const SizedBox(width: 4),
                      Text(
                        '添加 LoRA',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: c.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (field.hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text(
                field.hint!,
                style: TextStyle(fontSize: 11, color: c.muted),
              ),
            ),
          if (loras.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '未挂载 LoRA',
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ),
          ...List.generate(loras.length, (i) {
            final item = loras[i];
            final w = (_asDouble(item['weight']) ?? 1.0).clamp(-2.0, 2.0);
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _ParamTextField(
                      key: ValueKey('lora_${field.key}_$i'),
                      value: item['name']?.toString() ?? '',
                      style: TextStyle(fontSize: 12.5, color: c.ink),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: c.surface,
                        hintText: 'LoRA 名称',
                      ),
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
                    width: 100,
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
                    width: 38,
                    child: Text(
                      w.toStringAsFixed(2),
                      style: StyleLoomTheme.monoStyle(
                        fontSize: 11.5,
                        color: c.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 17,
                      color: c.muted,
                    ),
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
