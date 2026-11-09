import 'dart:async';

import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/http/dynamics.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/article/article_list/article.dart';
import 'package:PiliPlus/pages/article/listen/speech_text.dart';
import 'package:PiliPlus/common/widgets/node_slider.dart';
import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/pages/audio/widgets/transport_controls.dart';
import 'package:PiliPlus/pages/article/listen/controller.dart';
import 'package:PiliPlus/pages/article/listen/settings_view.dart';
import 'package:PiliPlus/services/shutdown_timer_service.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class ArticleListeningPage extends StatefulWidget {
  const ArticleListeningPage({
    super.key,
    required this.chunks,
    required this.title,
    this.cover,
    this.author,
    this.collectionId,
    this.articleId,
    this.opusId,
    this.handoffTimer = false,
  });
  final List<String> chunks;
  final String title;
  final String? cover;
  final String? author;
  final int? collectionId;
  final int? articleId;
  final String? opusId;
  final bool handoffTimer;
  @override
  State<ArticleListeningPage> createState() => _ArticleListeningPageState();
}

class _ArticleListeningPageState extends State<ArticleListeningPage>
    with SingleTickerProviderStateMixin {
  late final _plan = articleSpeechPlaybackPlan(widget.chunks);
  late final controller = ArticleListeningController(
    chunks: _plan.chunks,
    paragraphIndexes: _plan.paragraphIndexes,
    sourceParagraphs: widget.chunks,
    title: widget.title,
    cover: widget.cover,
    author: widget.author,
  );
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  bool _animatedPlaying = false;
  bool _compactCover = false;
  bool _handingOffTimer = false;
  final _lyricScroll = ScrollController();
  List<String>? _displayedItems;
  List<GlobalKey> _lyricKeys = [];
  int? _highlightedIndex;
  final _lyricVersion = ValueNotifier<int>(0);
  Future<List<ArticleListItemModel>>? _collection;

  @override
  void initState() {
    super.initState();
    controller.addListener(_updateAnimation);
    unawaited(controller.initialize());
  }

  void _updateAnimation() {
    final items = controller.displayTexts;
    final index = controller.currentParagraph;
    if (!controller.loading &&
        (!identical(_displayedItems, items) || _highlightedIndex != index)) {
      if (!identical(_displayedItems, items)) {
        _displayedItems = items;
        _lyricKeys = List.generate(items.length, (_) => GlobalKey());
      }
      _highlightedIndex = index;
      _lyricVersion.value++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _highlightedIndex != index ||
            index >= _lyricKeys.length) {
          return;
        }
        final target = _lyricKeys[index].currentContext;
        if (target != null) {
          unawaited(
            Scrollable.ensureVisible(
              target,
              alignment: .5,
              duration: const Duration(milliseconds: 550),
              curve: Curves.easeInOutCubic,
            ),
          );
        }
      });
    }
    if (_animatedPlaying == controller.wantsPlay) return;
    _animatedPlaying = controller.wantsPlay;
    if (controller.wantsPlay) {
      animation.forward();
    } else {
      animation.reverse();
    }
  }

  Future<void> _settings() async {
    SmartDialog.showLoading(msg: '正在打开语音设置…');
    try {
      await controller.prepareSettings();
      await SmartDialog.dismiss(status: SmartStatus.loading);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ArticleSpeechSettingsPage(
            settings: controller.settings,
            synthesizer: controller.synthesizer,
            onSave: controller.applySettings,
            onCacheCleared: controller.clearSessionCache,
          ),
        ),
      );
    } catch (_) {
      SmartDialog.showToast('语音设置打开失败，请从专栏阅读设置进入');
    } finally {
      await SmartDialog.dismiss(status: SmartStatus.loading);
      await controller.synthesizer.cancel();
      await controller.settingsClosed();
    }
  }

  Future<List<ArticleListItemModel>> _loadCollection() async {
    final id = widget.collectionId;
    if (id == null) return [];
    final result = await DynamicsHttp.articleList(id: id);
    if (result case Success(:final response)) return response.articles ?? [];
    throw StateError('文集加载失败');
  }

  Future<void> _openArticle(ArticleListItemModel item) async {
    Navigator.pop(context);
    if ((item.id != null && item.id == widget.articleId) ||
        (item.dynIdStr != null && item.dynIdStr == widget.opusId)) {
      return;
    }
    SmartDialog.showLoading(msg: '正在加载专栏…');
    try {
      List<String> chunks = [];
      String? title = item.title;
      String? cover = item.imageUrls?.firstOrNull;
      String? author;
      String? opusId = item.dynIdStr;
      if (item.id != null) {
        final result = await DynamicsHttp.articleView(cvId: item.id!);
        if (result case Success(:final response)) {
          title ??= response.title;
          cover ??= response.originImageUrls?.firstOrNull;
          author = response.author?.name;
          opusId ??= response.dynIdStr;
          chunks = articleSpeechChunks(
            title: title,
            opus: response.opus?.content,
            ops: response.ops,
            content: response.content,
          );
        }
      }
      if (opusId != null && opusId.isNotEmpty) {
        final result = await DynamicsHttp.opusDetail(opusId: opusId);
        if (result case Success(:final response)) {
          title ??= response.modules.moduleTag?.text;
          final opusChunks = articleSpeechChunks(
            title: title,
            opus: response.modules.moduleContent,
          );
          if (opusChunks.isNotEmpty) chunks = opusChunks;
          author ??= response.modules.moduleAuthor?.name;
        }
      }
      if (chunks.isEmpty) throw StateError('专栏正文加载失败或没有可朗读内容');
      await SmartDialog.dismiss(status: SmartStatus.loading);
      if (!mounted) return;
      _handingOffTimer = shutdownTimerService.beginAudioHandoff(
        controller.pause,
      );
      await controller.prepareArticleSwitch();
      if (!mounted) {
        if (_handingOffTimer) shutdownTimerService.reset();
        return;
      }
      final page = ArticleListeningPage(
        chunks: chunks,
        title: title ?? '专栏听书',
        cover: cover,
        author: author,
        collectionId: widget.collectionId,
        articleId: item.id,
        opusId: opusId,
        handoffTimer: _handingOffTimer,
      );
      unawaited(
        Navigator.pushReplacement<void, void>(
          context,
          MaterialPageRoute<void>(builder: (_) => page),
        ),
      );
    } catch (_) {
      if (_handingOffTimer && mounted) {
        shutdownTimerService.cancelAudioHandoff();
        _handingOffTimer = false;
      }
      if (mounted) controller.cancelArticleSwitch();
      SmartDialog.showToast('专栏正文加载失败，请重试');
    } finally {
      await SmartDialog.dismiss(status: SmartStatus.loading);
    }
  }

  void _playlist() {
    _collection ??= _loadCollection();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .65,
        child: FutureBuilder<List<ArticleListItemModel>>(
          future: _collection,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _collection = null;
                    _playlist();
                  },
                  child: const Text('文集加载失败，点击重试'),
                ),
              );
            }
            final articles = snapshot.data ?? [];
            if (articles.isEmpty) {
              return Center(
                child: Text(
                  widget.collectionId == null ? '当前专栏没有文集' : '文集暂无专栏',
                ),
              );
            }
            return Column(
              children: [
                const Padding(padding: EdgeInsets.all(16), child: Text('文集专栏')),
                Expanded(
                  child: ListView.builder(
                    itemCount: articles.length,
                    itemBuilder: (context, index) {
                      final item = articles[index];
                      final selected =
                          (item.id != null && item.id == widget.articleId) ||
                          (item.dynIdStr != null &&
                              item.dynIdStr == widget.opusId);
                      return ListTile(
                        selected: selected,
                        leading: Text('${index + 1}'),
                        title: Text(
                          item.title ?? '未命名专栏',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: selected ? const Icon(Icons.volume_up) : null,
                        onTap: () => unawaited(_openArticle(item)),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _speed() {
    var rate = controller.settings.rate;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '播放速度 ${rate.toStringAsFixed(2)}×',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              NodeSlider(
                min: .5,
                max: 2,
                divisions: 30,
                value: rate,
                label: '${rate.toStringAsFixed(2)}×',
                onChanged: (value) {
                  update(() => rate = value);
                  unawaited(controller.setRate(value, persist: false));
                },
                onChangeEnd: (value) => unawaited(controller.setRate(value)),
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('0.5×'), Text('2.0×')],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (!_handingOffTimer &&
        (shutdownTimerService.onPause == controller.pause ||
            widget.handoffTimer)) {
      shutdownTimerService
        ..onPause = null
        ..isPlaying = null
        ..reset();
    }
    controller.removeListener(_updateAnimation);
    controller.dispose();
    _lyricVersion.dispose();
    _lyricScroll.dispose();
    animation.dispose();
    super.dispose();
  }

  Widget _cover(ColorScheme scheme, double size) => InkWell(
    onTap: () => setState(() => _compactCover = !_compactCover),
    borderRadius: BorderRadius.circular(10),
    child: Semantics(
      button: true,
      label: _compactCover ? '切换大封面' : '切换小封面',
      child: widget.cover?.isNotEmpty == true
          ? NetworkImgLayer(
              src: widget.cover,
              width: size,
              height: size,
              cacheWidth: false,
            )
          : SizedBox(
              width: size,
              height: size,
              child: Icon(
                Icons.menu_book_rounded,
                size: size * .76,
                color: scheme.primary,
              ),
            ),
    ),
  );

  Widget _articleMetadata(ColorScheme scheme, {bool compact = false}) => Column(
    crossAxisAlignment: compact
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center,
    children: [
      Text(
        widget.title,
        textAlign: compact ? TextAlign.start : TextAlign.center,
        maxLines: compact ? 2 : 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16, height: 1.7),
      ),
      if (widget.author?.isNotEmpty == true)
        Text(
          widget.author!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: compact ? TextAlign.start : TextAlign.center,
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final articleText = ValueListenableBuilder<int>(
      valueListenable: _lyricVersion,
      builder: (context, _, _) {
        final items = _displayedItems ?? controller.displayTexts;
        if (_lyricKeys.length != items.length) {
          _lyricKeys = List.generate(items.length, (_) => GlobalKey());
        }
        return LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            controller: _lyricScroll,
            child: Column(
              children: [
                SizedBox(
                  height: (constraints.maxHeight / 2 - 24).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                for (var i = 0; i < items.length; i++)
                  Padding(
                    key: _lyricKeys[i],
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Align(
                      alignment: i == _highlightedIndex
                          ? Alignment.center
                          : Alignment.centerLeft,
                      child: Text(
                        items[i],
                        textAlign: i == _highlightedIndex
                            ? TextAlign.center
                            : TextAlign.start,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.7,
                          fontWeight: i == _highlightedIndex
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: i == _highlightedIndex
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  height: (constraints.maxHeight / 2 - 24).clamp(
                    0,
                    double.infinity,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('专栏听书'),
        actions: [
          IconButton(
            tooltip: '定时关闭',
            icon: const Icon(Icons.schedule),
            onPressed: () => shutdownTimerService
              ..onPause = controller.pause
              ..isPlaying = (() => controller.wantsPlay)
              ..showScheduleExitDialog(
                context,
                isFullScreen: false,
                isAudio: true,
              ),
          ),
          TextButton.icon(
            onPressed: _settings,
            icon: const Icon(Icons.settings_voice),
            label: const Text('语音设置'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
          child: ListenableBuilder(
            listenable: controller,
            child: articleText,
            builder: (context, articleText) => Column(
              children: [
                if (controller.loading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(controller.status)),
                      ],
                    ),
                  ),
                if (controller.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Text(
                          controller.error!,
                          style: TextStyle(color: scheme.error),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: controller.retry,
                              child: const Text('重试听书'),
                            ),
                            TextButton(
                              onPressed: _settings,
                              child: const Text('打开语音设置'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  child: _compactCover
                      ? Row(
                          children: [
                            _cover(scheme, 72),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _articleMetadata(scheme, compact: true),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _cover(scheme, 170),
                            const SizedBox(height: 12),
                            _articleMetadata(scheme),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                Expanded(child: articleText!),
                const SizedBox(height: 25),
                ProgressBar(
                  progress: controller.totalPosition.inSeconds,
                  total: controller.totalDuration.inSeconds,
                  baseBarColor: scheme.onSurface.withValues(alpha: .2),
                  progressBarColor: scheme.primary,
                  bufferedBarColor: Colors.transparent,
                  thumbColor: scheme.primary,
                  thumbGlowColor: scheme.primary.withValues(alpha: .3),
                  thumbGlowRadius: 0,
                  thumbRadius: 6,
                  minHeight: 36,
                  onSeek: controller.loading
                      ? null
                      : (ms) => controller.seek(Duration(milliseconds: ms)),
                ),
                SizedBox(
                  height: 30,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DurationUtils.formatDuration(
                          controller.totalPosition.inSeconds,
                        ),
                        style: TextStyle(fontSize: 13, color: scheme.outline),
                      ),
                      Text(
                        "${controller.totalIsEstimated ? '预计 ' : ''}${DurationUtils.formatDuration(controller.totalDuration.inSeconds)}",
                        style: TextStyle(fontSize: 13, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
                AudioTransportControls(
                  animation: animation,
                  onPrevious:
                      controller.loading || !controller.hasPreviousParagraph
                      ? null
                      : controller.previous,
                  onPlayPause: controller.ready ? controller.toggle : null,
                  onNext: controller.loading || !controller.hasNextParagraph
                      ? null
                      : controller.next,
                  leading: IconButton(
                    tooltip: '播放速度',
                    onPressed: controller.ready ? _speed : null,
                    icon: const Icon(Icons.speed_rounded, size: 26),
                  ),
                  trailing: IconButton(
                    tooltip: '文集列表',
                    onPressed: _playlist,
                    icon: const Icon(Icons.menu_rounded, size: 26),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
