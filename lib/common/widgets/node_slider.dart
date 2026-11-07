import 'package:material_ui/material_ui.dart';

class NodeSlider extends StatelessWidget {
  const NodeSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
    this.onChangeEnd,
  });
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 12,
        trackShape: const RoundedRectSliderTrackShape(),
        tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2.5),
        activeTickMarkColor: colors.onPrimary,
        inactiveTickMarkColor: colors.onSurfaceVariant,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
      ),
      child: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}
