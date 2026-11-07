import 'package:material_ui/material_ui.dart';

class AudioTransportControls extends StatelessWidget {
  const AudioTransportControls({
    super.key,
    required this.leading,
    required this.trailing,
    required this.animation,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    this.previousIcon = Icons.skip_previous_rounded,
    this.nextIcon = Icons.skip_next_rounded,
    this.previousTooltip = '上一段',
    this.nextTooltip = '下一段',
  });

  final IconData previousIcon;
  final IconData nextIcon;
  final String previousTooltip;
  final String nextTooltip;
  final Widget leading;
  final Widget trailing;
  final Animation<double> animation;
  final VoidCallback? onPrevious;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Center(child: leading)),
      Expanded(
        child: Center(
          child: IconButton(
            tooltip: previousTooltip,
            onPressed: onPrevious,
            icon: Icon(previousIcon, size: 40),
          ),
        ),
      ),
      Expanded(
        child: Center(
          child: IconButton(
            tooltip: '播放 / 暂停',
            onPressed: onPlayPause,
            icon: AnimatedIcon(
              size: 40,
              icon: AnimatedIcons.play_pause,
              progress: animation,
            ),
          ),
        ),
      ),
      Expanded(
        child: Center(
          child: IconButton(
            tooltip: nextTooltip,
            onPressed: onNext,
            icon: Icon(nextIcon, size: 40),
          ),
        ),
      ),
      Expanded(child: Center(child: trailing)),
    ],
  );
}
