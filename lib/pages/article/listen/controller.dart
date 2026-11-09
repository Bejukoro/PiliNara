import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/pages/article/listen/settings.dart';
import 'package:PiliPlus/pages/article/listen/speech_cache.dart';
import 'package:PiliPlus/pages/article/listen/speech_text.dart';
import 'package:PiliPlus/pages/article/listen/synthesizer.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/services/shutdown_timer_service.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

class ArticleListeningController extends ChangeNotifier {
  ArticleListeningController({
    required this.chunks,
    required this.title,
    this.cover,
    this.author,
    this.paragraphIndexes,
    this.sourceParagraphs,
  }) : assert(
         paragraphIndexes == null || paragraphIndexes.length == chunks.length,
       );
  List<String> chunks;
  final String title;
  final String? cover;
  final String? author;
  List<int>? paragraphIndexes;
  final List<String>? sourceParagraphs;
  bool _resumeAfterSettings = false;
  bool _settingsChanged = false;
  int _paragraphOf(int segment) => paragraphIndexes?[segment] ?? segment;
  final synthesizer = ArticleSynthesizer();
  final _persistentCache = ArticleSpeechCache();
  final _playerFuture = Player.create(
    configuration: PlayerConfiguration(
      options: {
        if (Platform.isAndroid) 'ao': Pref.audioOutput,
        'volume': '100',
      },
    ),
  );
  late final Player _player;
  bool _hasPlayer = false;
  bool _mediaLoaded = false;
  bool _settingsLoaded = false;
  bool _settingsOpen = false;
  bool _preparedForSwitch = false;
  bool _resumeAfterFailedSwitch = false;
  Future<ArticleSpeechSettings>? _settingsFuture;
  bool ready = false;
  Future<void>? _initialization;
  final _cache = <int, File>{};
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _tag = 'article-tts:${DateTime.now().microsecondsSinceEpoch}';
  ArticleSpeechSettings settings = ArticleSpeechSettings();
  Directory? _directory;
  AudioSession? _session;
  Future<void> _queue = Future.value();
  Future<void>? _prefetch;
  int? _prefetchIndex;
  int _speechRevision = 0;
  final _prefetchAttempted = <int>{};
  bool _closed = false;
  bool _wanted = false;
  bool _interrupted = false;
  bool loading = true;
  bool playing = false;
  String? error;
  String status = '正在初始化播放器';
  int index = 0;
  int _generation = 0;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  final _durations = <int, Duration>{};
  int? _openingIndex;
  Duration? _pendingSeek;

  late List<int> _characterCounts = chunks
      .map((text) => text.runes.length)
      .toList();

  double get _millisecondsPerCharacter {
    var characters = 0;
    var milliseconds = 0;
    for (final entry in _durations.entries) {
      characters += _characterCounts[entry.key];
      milliseconds += entry.value.inMilliseconds;
    }
    return characters == 0 ? 250 : milliseconds / characters;
  }

  int _segmentMilliseconds(int segment, double rate) =>
      _durations[segment]?.inMilliseconds ??
      (_characterCounts[segment] * rate).round().clamp(1, 1 << 31);

  Duration get totalDuration {
    final rate = _millisecondsPerCharacter;
    var milliseconds = 0;
    for (var i = 0; i < chunks.length; i++) {
      milliseconds += _segmentMilliseconds(i, rate);
    }
    return Duration(milliseconds: milliseconds);
  }

  Duration get totalPosition {
    final rate = _millisecondsPerCharacter;
    var milliseconds = position.inMilliseconds;
    for (var i = 0; i < index; i++) {
      milliseconds += _segmentMilliseconds(i, rate);
    }
    return Duration(
      milliseconds: milliseconds.clamp(0, totalDuration.inMilliseconds),
    );
  }

  bool get totalIsEstimated => _durations.length < chunks.length;

  int? _mediaIndex;
  Duration? _mediaDuration;
  bool get wantsPlay => _wanted;

  Future<void> initialize() => _initialization ??= _initialize();

  void _configurePlan() {
    final source = sourceParagraphs;
    if (source == null || source.isEmpty) return;
    final originalParagraph = _paragraphOf(index);
    final plan = settings.provider == SpeechProvider.microsoftDemo
        ? microsoftSpeechPlaybackPlan(source)
        : articleSpeechPlaybackPlan(source);
    chunks = plan.chunks;
    paragraphIndexes = plan.paragraphIndexes;
    _characterCounts = chunks.map((text) => text.runes.length).toList();
    index = 0;
    while (index + 1 < chunks.length &&
        _paragraphOf(index + 1) <= originalParagraph) {
      index++;
    }
  }

  List<String> get displayTexts =>
      settings.provider == SpeechProvider.microsoftDemo
      ? chunks
      : (sourceParagraphs ?? chunks);

  String get currentText => settings.provider == SpeechProvider.microsoftDemo
      ? chunks[index]
      : (sourceParagraphs?[_paragraphOf(index)] ?? chunks[index]);

  Future<void> ensureSettings() async {
    final value = await (_settingsFuture ??= ArticleSpeechSettings.load());
    if (!_settingsLoaded) {
      settings = value;
      _configurePlan();
    }
    _settingsLoaded = true;
  }

  Future<void> retry() async {
    if (ready) return select(index);
    loading = true;
    error = null;
    _initialization = null;
    _publish();
    await initialize();
  }

  Future<void> _initialize() async {
    try {
      status = '正在初始化播放器';
      _publish();
      if (!_hasPlayer) {
        _player = await _playerFuture.timeout(const Duration(seconds: 15));
        _hasPlayer = true;
      }
      status = '正在读取语音设置';
      _publish();
      await ensureSettings();
      if (_closed) return;
      _directory = await Directory(tmpDirPath).createTemp('article-tts-');
      status = '正在连接系统音频服务';
      _publish();
      _session = await AudioSession.instance.timeout(
        const Duration(seconds: 10),
      );
      if (_closed) return;
      await videoPlayerServiceHandler?.pause().timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
      if (_closed) return;
      await _session!
          .configure(const AudioSessionConfiguration.speech())
          .timeout(const Duration(seconds: 10));
      if (_closed) return;
      ready = true;
      _claimSession();
      _subscriptions.addAll([
        _player.stream.position.listen((value) {
          position = value;
          _publish();
        }),
        _player.stream.duration.listen((value) {
          if (!loading || _openingIndex == index) {
            duration = value;
            if (value > Duration.zero) _durations[index] = value;
          }
          _publish();
        }),
        _player.stream.playing.listen((value) {
          playing = value;
          _publish();
        }),
        _player.stream.completed.listen((value) {
          if (!value || loading || _closed || !_wanted) return;
          final generation = _generation;
          final completedIndex = index;
          // Android audio output may still contain samples when mpv reports
          // EOF. Opening the next file immediately flushes that output buffer.
          unawaited(_finishSegmentAfterDrain(generation, completedIndex));
        }),
        _player.stream.error.listen((_) {
          _mediaLoaded = false;
          loading = false;
          error = '音频播放失败，请重试当前片段';
          _wanted = false;
          unawaited(_player.pause());
          _publish();
        }),
        _session!.interruptionEventStream.listen((event) {
          if (event.begin) {
            _interrupted = _wanted;
            unawaited(pause(interruption: true));
          } else if (_interrupted &&
              event.type != AudioInterruptionType.unknown) {
            _interrupted = false;
            unawaited(play());
          }
        }),
        _session!.becomingNoisyEventStream.listen((_) {
          unawaited(pause());
        }),
      ]);
      if (!_settingsOpen) {
        await select(0);
      } else {
        loading = false;
        status = '可开始听书';
        _publish();
      }
    } catch (failure) {
      if (!_closed) {
        loading = false;
        final reason = failure is TimeoutException
            ? '超时'
            : failure is PlatformException
            ? failure.code
            : failure.runtimeType.toString();
        error = '$status失败（$reason），可重试或打开语音设置';
        _publish();
      }
    }
  }

  Future<void> _finishSegmentAfterDrain(
    int generation,
    int completedIndex,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (_closed ||
        !_wanted ||
        loading ||
        generation != _generation ||
        index != completedIndex) {
      return;
    }
    if (shutdownTimerService.isWaiting) {
      _wanted = false;
      shutdownTimerService.handleWaiting();
      _publish();
    } else if (index + 1 < chunks.length) {
      await select(index + 1);
    } else {
      _wanted = false;
      _publish();
    }
  }

  void _claimSession() {
    shutdownTimerService
      ..onPause = pause
      ..isPlaying = (() => _wanted);
    videoPlayerServiceHandler
      ?..currentHeroTag = _tag
      ..onPlay = play
      ..onPause = pause
      ..onStop = pause
      ..onSeek = seek
      ..onSkipToNext = next
      ..onSkipToPrevious = previous;
  }

  Future<void> select(int target, {Duration? startAt, bool play = true}) async {
    if (_closed ||
        _directory == null ||
        target < 0 ||
        target >= chunks.length) {
      return;
    }
    final generation = ++_generation;
    _pendingSeek = startAt;
    _wanted = play;
    shutdownTimerService.completeAudioHandoff();
    loading = true;
    _mediaLoaded = false;
    status = '正在准备第 ${_paragraphOf(target) + 1} 段';
    error = null;
    index = target;
    position = Duration.zero;
    duration = Duration.zero;
    _publish();
    final hasCachedAudio = _cache[target]?.existsSync() == true;
    if (!hasCachedAudio && (_prefetchIndex != target || _prefetch == null)) {
      await synthesizer.cancel();
    }
    _queue = _queue.then((_) async {
      if (_closed || generation != _generation) return;
      try {
        await _player.pause().timeout(const Duration(seconds: 5));
        if (_closed || generation != _generation) return;
        status =
            '正在调用${settings.provider.label}合成第 ${_paragraphOf(target) + 1} 段';
        _publish();
        final extension = settings.provider == SpeechProvider.microsoftDemo
            ? 'mp3'
            : 'wav';
        final path = '${_directory!.path}/$target-$generation.$extension';
        var file = _cache[target];
        if (file == null || !file.existsSync()) {
          file = await _synthesizeWithCache(
            target,
            path,
            isRelevant: () => !_closed && generation == _generation,
            onStatus: (value) {
              if (_closed || generation != _generation) return;
              status = value;
              _publish();
            },
          );
        }
        if (_closed || generation != _generation) return;
        _cache[target] = file;
        await _player.setRate(settings.rate);
        status = '正在打开合成音频';
        _publish();
        _openingIndex = target;
        await _player
            .open(Media(file.uri.toString()), play: false)
            .timeout(const Duration(seconds: 15));
        if (_closed || generation != _generation) return;
        // open() can finish before media_kit publishes its playlist stream.
        // Track our own successful open instead of recursively selecting while
        // this queue task is still running.
        if (error != null) throw StateError(error!);
        _mediaLoaded = true;
        _openingIndex = null;
        if (_pendingSeek case final targetPosition?) {
          _pendingSeek = null;
          await _player.seek(targetPosition);
          position = targetPosition;
        }
        loading = false;
        _publish();
        if (_wanted) await _startPlayback();
      } catch (failure) {
        if (_closed || generation != _generation) return;
        _openingIndex = null;
        loading = false;
        _wanted = false;
        error = failure is StateError
            ? failure.message.toString()
            : '语音合成失败，请检查网络和语音服务设置后重试';
        _publish();
      }
    });
    await _queue;
  }

  Future<void> play() async {
    if (_closed) return;
    _wanted = true;
    if (loading) {
      _publish();
      return;
    }
    if (error != null || !_mediaLoaded) {
      return select(index);
    }
    await _startPlayback();
  }

  Future<void> _startPlayback() async {
    if (_closed || !_mediaLoaded || error != null) return;
    if (_player.state.completed) await _player.seek(Duration.zero);
    _claimSession();
    _publish();
    if (await _session?.setActive(true) == false) {
      _wanted = false;
      _publish();
      return;
    }
    if (!_closed) {
      await _player.play();
      _preloadNext();
    }
  }

  void _preloadNext() {
    if (_closed || _settingsOpen || loading || !_wanted || _prefetch != null) {
      return;
    }
    final lastParagraph =
        _paragraphOf(index) +
        (settings.provider == SpeechProvider.qwen
            ? settings.qwenPrefetchParagraphs.clamp(
                0,
                ArticleSpeechSettings.maxQwenPrefetchParagraphs,
              )
            : 2);
    final microsoft = settings.provider == SpeechProvider.microsoftDemo;
    int? target;
    for (
      var candidate = index + 1;
      candidate < chunks.length &&
          (microsoft
              ? candidate <= index + 2
              : _paragraphOf(candidate) <= lastParagraph);
      candidate++
    ) {
      if (_cache[candidate]?.existsSync() != true &&
          !_prefetchAttempted.contains(candidate)) {
        target = candidate;
        break;
      }
    }
    if (target == null) return;
    final segment = target;
    final revision = _speechRevision;
    final generation = _generation;
    _prefetchAttempted.add(segment);
    _prefetchIndex = segment;
    late final Future<void> task;
    task = _queue.then((_) async {
      try {
        if (!_prefetchRelevant(segment, revision)) return;
        final extension = settings.provider == SpeechProvider.microsoftDemo
            ? 'mp3'
            : 'wav';
        final file = await _synthesizeWithCache(
          segment,
          '${_directory!.path}/prefetch-$revision-$segment.$extension',
          isRelevant: () => _prefetchRelevant(segment, revision),
        );
        if (_prefetchRelevant(segment, revision)) _cache[segment] = file;
      } catch (_) {
        if (!_closed &&
            revision == _speechRevision &&
            generation != _generation) {
          _prefetchAttempted.remove(segment);
        }
      } finally {
        if (identical(_prefetch, task)) {
          _prefetch = null;
          _prefetchIndex = null;
        }
      }
    });
    _prefetch = task;
    _queue = task;
    unawaited(task.whenComplete(_preloadNext));
  }

  Future<File> _synthesizeWithCache(
    int segment,
    String destination, {
    required bool Function() isRelevant,
    void Function(String)? onStatus,
  }) async {
    String? engine;
    String? voice;
    var cacheable = true;
    if (settings.provider == SpeechProvider.system) {
      try {
        // Android exposes the actual default engine and voice. Resolve both
        // before lookup and synthesize with that same explicit voice.
        if (!Platform.isAndroid) {
          cacheable = false;
        } else {
          engine = settings.systemEngine.isNotEmpty
              ? settings.systemEngine
              : await synthesizer.system.getDefaultEngine.timeout(
                  const Duration(seconds: 5),
                ) as String?;
          if (engine == null || engine.isEmpty) {
            cacheable = false;
          } else {
            await synthesizer
                .useSystemEngine(engine)
                .timeout(const Duration(seconds: 5));
            voice = settings.systemVoice;
            if (voice.isEmpty) {
              final fallback = await synthesizer.system.getDefaultVoice.timeout(
                const Duration(seconds: 5),
              );
              if (fallback is Map &&
                  fallback['name'] is String &&
                  fallback['locale'] is String &&
                  (fallback['locale'] as String)
                          .replaceAll('_', '-')
                          .toLowerCase() ==
                      settings.systemLocale
                          .replaceAll('_', '-')
                          .toLowerCase()) {
                voice = fallback['name'] as String;
              }
            }
            if (voice.isEmpty) cacheable = false;
          }
        }
      } catch (_) {
        cacheable = false;
      }
    }
    if (!isRelevant()) throw StateError('已取消合成');
    final extension = settings.provider == SpeechProvider.microsoftDemo
        ? 'mp3'
        : 'wav';
    final key = cacheable
        ? ArticleSpeechCache.keyFor(
            chunks[segment],
            settings,
            systemEngine: engine,
            systemVoice: voice,
          )
        : null;
    if (key != null) {
      try {
        final cached = await _persistentCache.restore(
          key,
          extension,
          destination,
        );
        if (!isRelevant()) throw StateError('已取消合成');
        if (cached != null) {
          onStatus?.call('正在使用本地语音缓存');
          return cached;
        }
      } on FileSystemException {
        /* Cache failures must not block playback. */
      }
    }
    if (!isRelevant()) throw StateError('已取消合成');
    final file = await synthesizer.synthesize(
      chunks[segment],
      settings,
      destination,
      onStatus: onStatus,
      resolvedSystemEngine: cacheable ? engine : null,
      resolvedSystemVoice: cacheable ? voice : null,
    );
    if (key != null && isRelevant()) {
      try {
        await _persistentCache.store(key, extension, file);
      } on FileSystemException {
        /* Playback still works if storage is full. */
      }
    }
    return file;
  }

  bool _prefetchRelevant(int target, int revision) =>
      !_closed &&
      !_settingsOpen &&
      revision == _speechRevision &&
      (target == index ||
          (target > index &&
              (settings.provider == SpeechProvider.microsoftDemo
                  ? target <= index + 2
                  : _paragraphOf(target) <=
                        _paragraphOf(index) +
                            (settings.provider == SpeechProvider.qwen
                                ? settings.qwenPrefetchParagraphs.clamp(
                                    0,
                                    ArticleSpeechSettings
                                        .maxQwenPrefetchParagraphs,
                                  )
                                : 2))));

  Future<void> pause({bool interruption = false}) async {
    if (!interruption) _interrupted = false;
    _wanted = false;
    if (ready && !_closed) await _player.pause();
    _publish();
  }

  void toggle() {
    if (_wanted) {
      unawaited(pause());
    } else {
      unawaited(play());
    }
  }

  int get currentParagraph => settings.provider == SpeechProvider.microsoftDemo
      ? index
      : _paragraphOf(index);
  bool get hasNextParagraph =>
      _paragraphOf(index) < _paragraphOf(chunks.length - 1);
  bool get hasPreviousParagraph => _paragraphOf(index) > _paragraphOf(0);

  void next() {
    final current = _paragraphOf(index);
    for (var target = index + 1; target < chunks.length; target++) {
      if (_paragraphOf(target) != current) {
        unawaited(select(target));
        return;
      }
    }
  }

  void previous() {
    final current = _paragraphOf(index);
    var target = index - 1;
    while (target >= 0 && _paragraphOf(target) == current) {
      target--;
    }
    if (target < 0) return;
    final previous = _paragraphOf(target);
    while (target > 0 && _paragraphOf(target - 1) == previous) {
      target--;
    }
    unawaited(select(target));
  }

  Future<void> seek(Duration target) async {
    if (_closed || loading || !_mediaLoaded) return;
    var remaining = target.inMilliseconds.clamp(
      0,
      totalDuration.inMilliseconds,
    );
    final rate = _millisecondsPerCharacter;
    var targetIndex = 0;
    while (targetIndex < chunks.length - 1) {
      final length = _segmentMilliseconds(targetIndex, rate);
      if (remaining < length) break;
      remaining -= length;
      targetIndex++;
    }
    final local = Duration(
      milliseconds: remaining.clamp(
        0,
        _segmentMilliseconds(targetIndex, rate),
      ),
    );
    if (targetIndex != index) {
      await select(targetIndex, startAt: local, play: _wanted);
    } else {
      await _player.seek(local);
      position = local;
      _publish();
    }
  }

  Future<void> setRate(double value, {bool persist = true}) async {
    if (!ready || _closed) return;
    settings.rate = value;
    if (ready) await _player.setRate(value);
    if (persist) await settings.save();
    _publish();
  }

  Future<void> prepareArticleSwitch() async {
    _resumeAfterFailedSwitch = _wanted;
    _settingsOpen = true;
    _wanted = false;
    ++_generation;
    await synthesizer.cancel();
    await _queue;
    if (_hasPlayer) await _player.pause().timeout(const Duration(seconds: 5));
    _preparedForSwitch = true;
  }

  void cancelArticleSwitch() {
    _settingsOpen = false;
    _preparedForSwitch = false;
    if (_resumeAfterFailedSwitch && !_closed) unawaited(play());
  }

  void clearSessionCache() {
    _cache.clear();
    _prefetchAttempted.clear();
  }

  Future<void> prepareSettings() async {
    _settingsOpen = true;
    _resumeAfterSettings = _wanted;
    _settingsChanged = false;
    _prefetchAttempted.clear();
    ++_speechRevision;
    await pause().timeout(const Duration(seconds: 3), onTimeout: () {});
    ++_generation;
    await synthesizer.cancel();
    await _queue;
    await ensureSettings();
    loading = false;
    _publish();
  }

  Future<void> applySettings(ArticleSpeechSettings value) async {
    ++_speechRevision;
    await pause();
    ++_generation;
    await synthesizer.cancel();
    await _queue;
    await value.save();
    settings = value;
    _configurePlan();
    _settingsLoaded = true;
    _settingsChanged = true;
    if (!ready) return;
    await _player.stop();
    _cache.clear();
    _durations.clear();
    _prefetchAttempted.clear();
    final directory = _directory;
    if (directory != null) {
      for (final file in directory.listSync().whereType<File>()) {
        await file.delete();
      }
    }
  }

  Future<void> settingsClosed() async {
    _settingsOpen = false;
    if (_closed) return;
    if (_settingsChanged) {
      if (!ready) {
        await retry();
      } else {
        await select(index, play: _resumeAfterSettings);
      }
    } else if (_resumeAfterSettings) {
      await play();
    }
  }

  void _publish() {
    if (_closed) return;
    final handler = videoPlayerServiceHandler;
    if (handler?.currentHeroTag == _tag) {
      if (_mediaIndex != index || _mediaDuration != totalDuration) {
        _mediaIndex = index;
        _mediaDuration = totalDuration;
        handler!.mediaItem.add(
          MediaItem(
            id: _tag,
            title: title,
            artist: author,
            album:
                '专栏听书 · ${_paragraphOf(index) + 1}/${_paragraphOf(chunks.length - 1) + 1}',
            artUri: Uri.tryParse(cover ?? ''),
            duration: totalDuration,
          ),
        );
      }
      handler!.playbackState.add(
        PlaybackState(
          processingState: loading
              ? AudioProcessingState.buffering
              : AudioProcessingState.ready,
          // Preserve play intent during synthesis so Android keeps the
          // foreground audio session alive between speech fragments.
          playing: _wanted,
          updatePosition: totalPosition,
          speed: settings.rate,
          controls: [
            MediaControl.skipToPrevious,
            _wanted ? MediaControl.pause : MediaControl.play,
            MediaControl.skipToNext,
            MediaControl.stop,
          ],
          androidCompactActionIndices: const [0, 1, 2],
          systemActions: const {
            MediaAction.seek,
            MediaAction.skipToPrevious,
            MediaAction.skipToNext,
          },
        ),
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    if (ready) unawaited(_player.pause());
    _closed = true;
    ++_generation;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    final handler = videoPlayerServiceHandler;
    final ownsSession = handler?.currentHeroTag == _tag;
    if (ownsSession) {
      handler!
        ..onPlay = null
        ..onPause = null
        ..onStop = null
        ..onSeek = null
        ..onSkipToNext = null
        ..onSkipToPrevious = null
        ..currentHeroTag = null;
      handler.mediaItem.add(null);
      handler.playbackState.add(
        PlaybackState(processingState: AudioProcessingState.idle),
      );
    }
    unawaited(_cleanup(ownsSession));
    super.dispose();
  }

  Future<void> _cleanup(bool ownsSession) async {
    await synthesizer.dispose(skipCancel: _preparedForSwitch);
    await _initialization;
    await _queue;
    await (await _playerFuture).dispose();
    if (ownsSession && videoPlayerServiceHandler?.currentHeroTag == null) {
      await _session?.setActive(false);
    }
    final directory = _directory;
    if (directory != null && directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}
