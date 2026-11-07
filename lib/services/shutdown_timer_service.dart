// 定时关闭服务

import 'dart:async' show Timer;

import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/common/widgets/node_slider.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/widgets/menu_row.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:collection/collection.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPicker;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:material_ui/material_ui.dart';

const _kSqueeze = 1.25;
const _kItemExtent = 38.0;

enum _ShutdownType with EnumWithLabel {
  pause('暂停视频'),
  exit('退出APP'),
  ;

  @override
  final String label;
  const _ShutdownType(this.label);
}

final shutdownTimerService = ShutdownTimerService._internal();

class ShutdownTimerService {
  ShutdownTimerService._internal();

  VoidCallback? onPause;
  ValueGetter<bool>? isPlaying;

  DateTime? _deadline;
  DateTime? get deadline => _deadline;
  Timer? _shutdownTimer;
  bool get isActive => _shutdownTimer?.isActive ?? false;
  int _durationInMinutes = 0;
  _ShutdownType _shutdownType = .pause;

  bool _isWaiting = false;
  bool get isWaiting => _isWaiting;
  bool _waitUntilCompleted = false;
  bool _isAudioTimer = false;
  bool _audioHandoff = false;
  bool _deferredShutdown = false;

  void _stopTimer() {
    if (_shutdownTimer != null) {
      _deadline = null;
      _shutdownTimer!.cancel();
      _shutdownTimer = null;
    }
  }

  void reset([int durationInMinutes = 0]) {
    _stopTimer();
    _isWaiting = false;
    _durationInMinutes = durationInMinutes;
    _isAudioTimer = false;
    _audioHandoff = false;
    _deferredShutdown = false;
  }

  void _startShutdownTimer(int durationInMinutes, {bool isAudio = false}) {
    reset(durationInMinutes);
    _isAudioTimer = isAudio;
    if (durationInMinutes == 0) {
      SmartDialog.showToast('取消定时关闭');
      return;
    }
    SmartDialog.showToast('设置 ${_format(durationInMinutes)} 后定时关闭');
    _deadline = DateTime.now().add(Duration(minutes: durationInMinutes));
    _shutdownTimer = Timer(
      Duration(minutes: durationInMinutes),
      _handleShutdown,
    );
  }

  void _handleShutdown() {
    _deadline = null;
    _shutdownTimer = null;
    if (_isAudioTimer && _audioHandoff) {
      _deferredShutdown = true;
      return;
    }
    if (_isAudioTimer && onPause == null) {
      reset();
      return;
    }
    switch (_shutdownType) {
      case .pause:
        late final player = PlPlayerController.instance;
        final isPlaying =
            this.isPlaying?.call() ??
            (!_isAudioTimer && player?.playerStatus.isPlaying == true);
        if (isPlaying) {
          if (_waitUntilCompleted) {
            _isWaiting = true;
          } else {
            _durationInMinutes = 0;
            (onPause ?? (_isAudioTimer ? null : player?.pause))?.call();
            SmartDialog.showToast('定时时间已到，已暂停');
          }
        }
      case .exit:
        if (_waitUntilCompleted) {
          final isPlaying =
              this.isPlaying?.call() ??
              (!_isAudioTimer &&
                  PlPlayerController.instance?.playerStatus.isPlaying == true);
          if (isPlaying) {
            _isWaiting = true;
            return;
          }
        }
        _syncProgressAndExit();
    }
  }

  /// Keeps the active audio timer while a new article replaces the current one.
  bool beginAudioHandoff(VoidCallback owner) {
    if (!_isAudioTimer || onPause != owner || (!isActive && !_isWaiting)) {
      return false;
    }
    _audioHandoff = true;
    return true;
  }

  void completeAudioHandoff() {
    if (!_audioHandoff) return;
    _audioHandoff = false;
    if (_isWaiting) {
      if (_shutdownType == _ShutdownType.pause) {
        handleWaiting();
        onPause?.call();
      } else {
        handleWaiting();
      }
    } else if (_deferredShutdown) {
      _deferredShutdown = false;
      _handleShutdown();
    }
  }

  void cancelAudioHandoff() {
    if (!_audioHandoff) return;
    _audioHandoff = false;
    if (_deferredShutdown) {
      _deferredShutdown = false;
      _handleShutdown();
    }
  }

  void handleWaiting() {
    switch (_shutdownType) {
      case .pause:
        _isWaiting = false;
        _durationInMinutes = 0;
        SmartDialog.showToast('定时时间已到，已暂停');
      case .exit:
        _syncProgressAndExit();
    }
  }

  void _syncProgressAndExit() {
    if (!_isAudioTimer && PlPlayerController.instance != null) {
      final player = PlPlayerController.instance!;
      final res = player.makeHeartBeat(
        player.position.value,
        type: .completed,
        isManual: true,
      );
      if (res != null) {
        res.whenComplete(DeviceUtils.exitApp);
        return;
      }
    }
    DeviceUtils.exitApp();
  }

  static (int hour, int minute) _parseMinutes(int minutes) =>
      (minutes ~/ 60, minutes % 60);

  static String _format(int minutes) {
    if (minutes == 60) return '60分钟';
    final (int hour, int minute) = _parseMinutes(minutes);
    if (hour > 0 && minute > 0) {
      return '$hour小时$minute分钟';
    } else if (hour > 0) {
      return '$hour小时';
    } else {
      return '$minute分钟';
    }
  }

  Widget _pickerBuider(
    int count, {
    required ValueChanged<int> onSelectedItemChanged,
    required FixedExtentScrollController scrollController,
  }) {
    return CupertinoPicker(
      // looping: true,
      squeeze: _kSqueeze,
      itemExtent: _kItemExtent,
      scrollController: scrollController,
      onSelectedItemChanged: onSelectedItemChanged,
      children: List.generate(
        count,
        (index) => Center(
          child: Text(
            index.toString().padLeft(2, '0'),
            style: const TextStyle(fontSize: 20, letterSpacing: .4),
          ),
        ),
      ),
    );
  }

  void _showTimePickerDialog(
    BuildContext context,
    VoidCallback onCountdown,
    StateSetter setState, {
    bool isAudio = false,
  }) {
    final values = _parseMinutes(_durationInMinutes);
    var hour = values.$1;
    var minute = values.$2;

    final hourController = FixedExtentScrollController(initialItem: hour);
    final minuteController = FixedExtentScrollController(initialItem: minute);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const .fromLTRB(20, 6, 20, 0),
        actionsPadding: const .fromLTRB(20, 0, 20, 16),
        constraints: const .tightFor(width: 320, height: 320),
        content: Row(
          children: [
            Expanded(
              child: _pickerBuider(
                25,
                scrollController: hourController,
                onSelectedItemChanged: (value) => hour = value,
              ),
            ),
            const Text('时'),
            const SizedBox(width: 10),
            Expanded(
              child: _pickerBuider(
                60,
                scrollController: minuteController,
                onSelectedItemChanged: (value) => minute = value,
              ),
            ),
            const Text('分'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(color: ColorScheme.of(context).outline),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _startShutdownTimer(hour * 60 + minute, isAudio: isAudio);
              onCountdown();
              setState(() {});
            },
            child: const Text('确认'),
          ),
        ],
      ),
    ).whenComplete(() {
      hourController.dispose();
      minuteController.dispose();
    });
  }

  void _showAudioTimerDialog(BuildContext context) {
    var minutes = _durationInMinutes;
    const presets = {0, 5, 10, 15, 20, 30, 45, 60, 90, 120};
    var options = {...presets, minutes}.sorted(Comparable.compare);
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 512),
      builder: (context) => ShutdownPanel(
        builder: (context, countdown, onCountdown, setState) {
          final label = minutes == 0 ? '关闭定时' : _format(minutes);
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '音频定时关闭',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      countdown,
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(label),
                  NodeSlider(
                    value: options.indexOf(minutes).toDouble(),
                    min: 0,
                    max: (options.length - 1).toDouble(),
                    divisions: options.length - 1,
                    label: label,
                    onChanged: (value) =>
                        setState(() => minutes = options[value.round()]),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [const Text('关闭'), Text(_format(options.last))],
                  ),
                  TextButton(
                    onPressed: () => _showTimePickerDialog(
                      context,
                      onCountdown,
                      (change) => setState(() {
                        change();
                        minutes = _durationInMinutes;
                        options = {
                          ...presets,
                          minutes,
                        }.sorted(Comparable.compare);
                      }),
                      isAudio: true,
                    ),
                    child: const Text('自定义时间'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('等待当前音频播放完毕'),
                    subtitle: const Text('专栏听书将在当前片段结束后执行'),
                    value: _waitUntilCompleted,
                    onChanged: (value) =>
                        setState(() => _waitUntilCompleted = value),
                  ),
                  Wrap(
                    spacing: 12,
                    children: [
                      for (final type in _ShutdownType.values)
                        ChoiceChip(
                          label: Text(
                            type == _ShutdownType.pause ? '暂停音频' : '退出 App',
                          ),
                          selected: _shutdownType == type,
                          onSelected: (_) =>
                              setState(() => _shutdownType = type),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      _startShutdownTimer(minutes, isAudio: true);
                      Navigator.pop(context);
                    },
                    child: Text(minutes == 0 ? '关闭定时' : '开始计时'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void showScheduleExitDialog(
    BuildContext context, {
    required bool isFullScreen,
    bool isLive = false,
    bool isAudio = false,
  }) {
    if (isAudio) {
      _showAudioTimerDialog(context);
      return;
    }
    const Set<int> scheduleTimeMinutes = {0, 15, 30, 45, 60};
    const TextStyle titleStyle = TextStyle(fontSize: 14);
    if (isLive) {
      _waitUntilCompleted = false;
    }

    final child = ShutdownPanel(
      builder: (context, countdown, onCountdown, setState) {
        final theme = Theme.of(context);
        return Padding(
          padding: const .all(12),
          child: Material(
            clipBehavior: .hardEdge,
            color: theme.colorScheme.surface,
            borderRadius: const .all(.circular(12)),
            child: ListView(
              padding: const .symmetric(vertical: 14),
              children: [
                Stack(
                  alignment: .center,
                  clipBehavior: .none,
                  children: [
                    const Text('定时关闭', style: titleStyle),
                    Positioned(top: 0, bottom: 0, right: 16, child: countdown),
                  ],
                ),
                const SizedBox(height: 10),
                ...{...scheduleTimeMinutes, _durationInMinutes}
                    .sorted(Comparable.compare)
                    .map(
                      (minutes) => ListTile(
                        dense: true,
                        onTap: () {
                          Navigator.pop(context);
                          _startShutdownTimer(minutes);
                        },
                        title: Text(
                          switch (minutes) {
                            0 => '禁用',
                            _ => _format(minutes),
                          },
                          style: titleStyle,
                        ),
                        trailing: _durationInMinutes == minutes
                            ? Icon(
                                size: 20,
                                Icons.done,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                      ),
                    ),
                ListTile(
                  dense: true,
                  onTap: () =>
                      _showTimePickerDialog(context, onCountdown, setState),
                  title: const Text('自定义', style: titleStyle),
                ),
                if (!isLive) ...[
                  Builder(
                    builder: (context) {
                      void onChanged([_]) {
                        _waitUntilCompleted = !_waitUntilCompleted;
                        (context as Element).markNeedsBuild();
                      }

                      return ListTile(
                        dense: true,
                        onTap: onChanged,
                        title: const Text('额外等待视频播放完毕', style: titleStyle),
                        trailing: Transform.scale(
                          alignment: .centerRight,
                          scale: 0.8,
                          child: Switch(
                            value: _waitUntilCompleted,
                            onChanged: onChanged,
                          ),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 5),
                Padding(
                  padding: const .only(left: 18),
                  child: Builder(
                    builder: (context) {
                      return Row(
                        spacing: 12,
                        children: [
                          const Text('倒计时结束:', style: titleStyle),
                          ..._ShutdownType.values.map(
                            (e) => ActionRowLineItem(
                              onTap: () {
                                _shutdownType = e;
                                (context as Element).markNeedsBuild();
                              },
                              text: ' ${e.label} ',
                              selectStatus: _shutdownType == e,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    PageUtils.showVideoBottomSheet(
      context,
      maxWidth: 512,
      child: isLive ? Theme(data: ThemeUtils.darkTheme, child: child) : child,
    );
  }
}

typedef ShutdownStatefulWidgetBuilder = Widget Function(
  BuildContext context,
  Widget countdown,
  VoidCallback onCountdown,
  StateSetter setState,
);

class ShutdownPanel extends StatefulWidget {
  const ShutdownPanel({
    super.key,
    required this.builder,
    this.buildCountdownText = _kBuildCountdownText,
  });

  final ShutdownStatefulWidgetBuilder builder;
  final Widget Function(String? text) buildCountdownText;

  static Widget _kBuildCountdownText(String? text) {
    if (text == null) {
      return const SizedBox.shrink();
    }
    return Text(text);
  }

  @override
  State<ShutdownPanel> createState() => _ShutdownPanelState();
}

class _ShutdownPanelState extends State<ShutdownPanel> with ShutdownMixin {
  @override
  Widget build(BuildContext context) {
    final countdown = Obx(() => widget.buildCountdownText(countdownText.value));
    return widget.builder(context, countdown, _startTimer, setState);
  }
}

mixin ShutdownMixin<T extends StatefulWidget> on State<T> {
  Timer? _countdownTimer;
  final RxnString countdownText = RxnString(null);

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _updateCountdownTextEnd([String? value]) {
    _stopTimer();
    countdownText.value = value;
  }

  bool _updateCountdownText([_]) {
    if (shutdownTimerService.isWaiting) {
      _updateCountdownTextEnd('当前播放结束后关闭');
      return false;
    }
    final deadline = shutdownTimerService.deadline;
    if (deadline == null) {
      _updateCountdownTextEnd();
      return false;
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= .zero) {
      _updateCountdownTextEnd();
      return false;
    }
    countdownText.value = DurationUtils.formatDuration(remaining.inSeconds);
    return true;
  }

  void _startTimer() {
    _stopTimer();
    if (_updateCountdownText()) {
      _countdownTimer = .periodic(
        const Duration(seconds: 1),
        _updateCountdownText,
      );
    }
  }

  void _stopTimer() {
    if (_countdownTimer != null) {
      _countdownTimer!.cancel();
      _countdownTimer = null;
    }
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
