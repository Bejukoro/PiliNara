import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/flutter/popup_menu.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/gesture/horizontal_drag_gesture_recognizer.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/mini_scaffold.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart'
    show tabBarScrollPhysics;
import 'package:PiliPlus/pages/article/widgets/reading_settings.dart';
import 'package:PiliPlus/utils/font_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_to_box_adapter.dart';
import 'package:PiliPlus/models/common/image_preview_type.dart';
import 'package:PiliPlus/models/dynamics/article_content_model.dart' show Pic;
import 'package:PiliPlus/models/dynamics/result.dart' show DynamicStat, Tribee;
import 'package:PiliPlus/pages/article/controller.dart';
import 'package:PiliPlus/pages/article/listen/speech_text.dart';
import 'package:PiliPlus/pages/article/listen/view.dart';
import 'package:PiliPlus/pages/article/listen/settings.dart';
import 'package:PiliPlus/pages/article/listen/settings_view.dart';
import 'package:PiliPlus/pages/article/listen/synthesizer.dart';
import 'package:PiliPlus/pages/article/widgets/article_ops.dart';
import 'package:PiliPlus/pages/article/widgets/html_render.dart';
import 'package:PiliPlus/pages/article/widgets/opus_content.dart';
import 'package:PiliPlus/pages/article/widgets/sliver_list_ext.dart';
import 'package:PiliPlus/pages/article/widgets/sliver_to_box_adapter.dart';
import 'package:PiliPlus/pages/common/dyn/common_dyn_page.dart';
import 'package:PiliPlus/pages/dynamics_repost/view.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:html/parser.dart' as parser;
import 'package:material_ui/material_ui.dart';

class ArticlePage extends StatefulWidget {
  const ArticlePage({super.key});

  @override
  State<ArticlePage> createState() => _ArticlePageState();
}

class _ArticlePageState extends CommonDynPageState<ArticlePage>
    with DynReplyLocateStateMixin {
  @override
  late final ArticleController controller;
  @override
  bool get isArticle => true;

  @override
  dynamic get arguments => {'id': controller.id};

  StreamSubscription<dynamic>? _readingSettingsSubscription;
  ArticleReadingSettings readingSettings = ArticleReadingSettings.load();

  Future<void> _loadReadingFont() async {
    final family = readingSettings.fontFamily;
    if (family == null) return;
    await FontUtils.loadFontIfNecessary(family);
    if (mounted) setState(() {});
  }

  Future<void> _showReadingSettings() async {
    setState(() => readingSettings = ArticleReadingSettings.load());
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: theme.colorScheme.surface,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      builder: (_) => ArticleReadingSettingsPanel(
        settings: readingSettings,
        onSpeechSettings: _showSpeechSettings,
        onChanged: (value) {
          setState(() => readingSettings = value);
          value.save().catchError((Object error) {
            SmartDialog.showToast('阅读设置保存失败，请重试');
          });
        },
      ),
    );
  }

  UniqueKey? _centerKey;

  Future<void> _showSpeechSettings() async {
    final synthesizer = ArticleSynthesizer();
    SmartDialog.showLoading(msg: '正在打开语音设置…');
    try {
      final settings = await ArticleSpeechSettings.load();
      await SmartDialog.dismiss(status: SmartStatus.loading);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ArticleSpeechSettingsPage(
            settings: settings,
            synthesizer: synthesizer,
            onSave: (value) => value.save(),
          ),
        ),
      );
    } catch (_) {
      SmartDialog.showToast('语音设置加载失败，请重试');
    } finally {
      await SmartDialog.dismiss(status: SmartStatus.loading);
      await synthesizer.dispose();
    }
  }

  bool get reverse => _centerKey != null;

  @override
  void initState() {
    final params = Get.parameters;
    controller = Get.putOrFind(
      ArticleController.new,
      tag: params['type']! + params['id']!,
    );
    if (params.containsKey('viewComment') || controller.rootRpId != null) {
      _centerKey = UniqueKey();
    }
    super.initState();
    _loadReadingFont();
    _readingSettingsSubscription = GStorage.setting
        .watch(key: SettingBoxKey.articleReadingSettings)
        .listen((_) {
          if (!mounted) return;
          setState(() => readingSettings = ArticleReadingSettings.load());
          _loadReadingFont();
        });
  }

  @override
  void dispose() {
    _readingSettingsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final readerTheme = readingSettings.readerTheme(baseTheme);
    theme = readerTheme;
    final page = Theme(
      data: readerTheme,
      child: Builder(
        builder: (_) => fabAnimWrapper(
          child: SimpleScaffold(
            backgroundColor: readingSettings.backgroundFor(
              baseTheme.brightness,
            ),
            appBar: _buildAppBar(),
            body: Padding(
              padding: .only(left: padding.left, right: padding.right),
              child: _buildPage(),
            ),
            fab: SlideTransition(
              position: fabAnimation,
              child: _buildBottom(),
            ),
          ),
        ),
      ),
    );
    final overlay =
        readerTheme.appBarTheme.systemOverlayStyle ??
        (baseTheme.brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark)
            .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarDividerColor: Colors.transparent,
              systemStatusBarContrastEnforced: false,
              systemNavigationBarContrastEnforced: false,
            );
    return AnnotatedRegion<SystemUiOverlayStyle>(value: overlay, child: page);
  }

  Widget _buildPage() {
    double padding = max(maxWidth / 2 - Grid.smallCardWidth, 0);
    if (isPortrait) {
      return Padding(
        padding: .symmetric(horizontal: padding),
        child: SelectionArea(
          child: CustomScrollView(
            primary: true,
            key: _centerKey,
            center: _centerKey,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _buildContent(
                max(
                  1,
                  maxWidth -
                      this.padding.horizontal -
                      2 * padding -
                      2 * readingSettings.pageMargin,
                ),
              ),
              SelectionContainer.disabled(
                child: SliverToBoxAdapter(
                  child: Divider(
                    thickness: 8,
                    color: theme.dividerColor.withValues(alpha: 0.05),
                  ),
                ),
              ),
              SelectionContainer.disabled(
                key: _centerKey,
                child: buildReplyHeader(),
              ),
              SelectionContainer.disabled(
                child: Obx(() => replyList(controller.loadingState.value)),
              ),
            ],
          ),
        ),
      );
    }

    _centerKey = null;
    padding = padding / 4;
    final flex = controller.ratio[0].toInt();
    final flex1 = controller.ratio[1].toInt();
    return Row(
      crossAxisAlignment: .start,
      children: [
        Expanded(
          flex: flex,
          child: SelectionArea(
            child: CustomScrollView(
              primary: true,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: .only(
                    left: padding,
                    bottom: this.padding.bottom + 100,
                  ),
                  sliver: _buildContent(
                    max(
                      1,
                      (maxWidth - this.padding.horizontal) *
                              flex /
                              (flex + flex1) -
                          padding -
                          8 -
                          2 * readingSettings.pageMargin,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        VerticalDivider(
          thickness: 8,
          color: theme.dividerColor.withValues(alpha: 0.05),
        ),
        Expanded(
          flex: flex1,
          child: Padding(
            padding: .only(right: padding),
            child: MiniScaffold(
              body: refreshIndicator(
                onRefresh: controller.onRefresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    buildReplyHeader(),
                    Obx(() => replyList(controller.loadingState.value)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(double maxWidth) => SliverPadding(
    padding: EdgeInsets.symmetric(
      horizontal: readingSettings.pageMargin,
      vertical: 8,
    ),
    sliver: Obx(() {
      if (controller.isLoaded.value) {
        final Widget content;
        late final modules = controller.opusData?.modules;
        if (controller.opus != null) {
          // if (kDebugMode) debugPrint('json page');
          content = OpusContent(
            opus: controller.opus!,
            images: controller.images,
            maxWidth: maxWidth,
            opusId: controller.id,
            reverse: reverse,
            readingSettings: readingSettings,
          );
        } else if (modules?.moduleBlocked case final moduleBlocked?) {
          // if (kDebugMode) debugPrint('moduleBlocked');
          content = SliverToBoxAdapter(
            child: moduleBlockedItem(context, theme.colorScheme, moduleBlocked),
          );
        } else if (controller.articleData?.content != null) {
          if (controller.articleData?.type == 3) {
            // json
            content = ArticleOpus(
              reverse: reverse,
              ops: controller.articleData?.ops,
              readingSettings: readingSettings,
              maxWidth: maxWidth,
            );
          } else {
            // if (kDebugMode) debugPrint('html page');
            final res = parser.parse(controller.articleData!.content!);
            if (res.body!.children.isEmpty) {
              content = SliverToBoxAdapter(
                child: htmlRender(
                  context: context,
                  html: controller.articleData!.content!,
                  maxWidth: maxWidth,
                  readingSettings: readingSettings,
                  readingBackground: readingSettings.backgroundFor(
                    Theme.of(context).brightness,
                  ),
                ),
              );
            } else {
              content = SliverListExt.separated(
                reverse: reverse,
                itemCount: res.body!.children.length,
                itemBuilder: (context, index) {
                  return htmlRender(
                    context: context,
                    element: res.body!.children[index],
                    maxWidth: maxWidth,
                    readingSettings: readingSettings,
                    readingBackground: readingSettings.backgroundFor(
                      Theme.of(this.context).brightness,
                    ),
                  );
                },
                separatorBuilder: (_, _) =>
                    SizedBox(height: readingSettings.paragraphSpacing),
              );
            }
          }
        } else {
          content = const SliverToBoxAdapter(child: Text('NULL'));
        }

        final isOpus = controller.type != 'read';
        final headerPics = modules?.moduleTop?.display?.album?.pics;
        final cover = controller.summary.cover;

        return SliverMainAxisGroup(
          slivers: [
            if (headerPics != null && headerPics.isNotEmpty)
              SliverToBoxAdapter(child: _buildImageGallery(headerPics))
            else if (cover != null && cover.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildImageGallery([
                  Pic.fromJson({'url': cover}),
                ]),
              ),
            if (controller.summary.title != null)
              SliverToBoxWithVisibilityAdapter(
                onVisibilityChanged: controller.showTitle.call,
                child: Text(
                  controller.summary.title!,
                  style: TextStyle(
                    fontSize: readingSettings.fontSize * 17 / 16,
                    height: readingSettings.lineHeight,
                    fontFamily: readingSettings.fontFamily,
                    fontWeight: .bold,
                  ),
                ),
              ),
            SliverToBoxAdapter(child: _buildAuthor()),
            if (isOpus) ...?modules?.moduleTribee?.items?.map(_buildTribee),
            if (isOpus && modules?.moduleCollection != null)
              SliverToBoxAdapter(
                child: SelectionContainer.disabled(
                  child: opusCollection(
                    theme.colorScheme,
                    modules!.moduleCollection!,
                  ),
                ),
              ),
            DefaultTextStyle.merge(
              style: readingSettings.textStyle,
              child: content,
            ),
          ],
        );
      }

      return const SliverToBoxAdapter();
    }),
  );

  Widget _buildTribee(Tribee tribee) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const .only(bottom: 8),
        child: Material(
          borderRadius: Style.borderRadius6,
          color: colorScheme.onInverseSurface,
          child: InkWell(
            borderRadius: Style.borderRadius6,
            onTap: tribee.jumpUrl == null
                ? null
                : () => PiliScheme.routePushFromUrl(tribee.jumpUrl!),
            child: Padding(
              padding: const .symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  NetworkImgLayer(
                    src: tribee.faceUrl,
                    width: 30,
                    height: 30,
                    borderRadius: Style.borderRadius6,
                  ),
                  const SizedBox(width: 10),
                  Text('${tribee.name}${tribee.suffix ?? ''}'),
                  SizedBox(
                    height: 20,
                    child: VerticalDivider(
                      width: 20,
                      color: colorScheme.outline.withValues(alpha: .4),
                    ),
                  ),
                  Text(
                    '${tribee.dynCountText ?? ''} · ${tribee.latestTimeText ?? ''}',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
    title: Obx(() {
      if (controller.isLoaded.value && controller.showTitle.value) {
        return Text(controller.summary.title!);
      }
      return const SizedBox.shrink();
    }),
    actions: [
      IconButton(
        tooltip: '听书',
        icon: const Icon(Icons.headphones_outlined),
        onPressed: () {
          if (!controller.isLoaded.value) return;
          final chunks = articleSpeechChunks(
            title: controller.summary.title,
            opus: controller.opus,
            ops: controller.articleData?.ops,
            content: controller.articleData?.content,
          );
          if (chunks.isEmpty) {
            SmartDialog.showToast('当前专栏没有可朗读的正文');
            return;
          }
          Get.to(
            () => ArticleListeningPage(
              chunks: chunks,
              collectionId: controller.opusData?.modules.moduleCollection?.id,
              articleId: controller.commentId,
              opusId: controller.type == 'opus' ? controller.id : null,
              title: controller.summary.title ?? '专栏听书',
              cover: controller.summary.cover,
              author: controller.summary.author?.name,
            ),
          );
        },
      ),
      IconButton(
        tooltip: '阅读设置',
        onPressed: _showReadingSettings,
        icon: const Icon(Icons.text_fields),
      ),
      const SizedBox(width: 4),
      if (!isPortrait) ratioWidget(maxWidth),
      IconButton(
        tooltip: '浏览器打开',
        onPressed: () => PageUtils.inAppWebview(controller.url),
        icon: const Icon(Icons.open_in_browser_outlined, size: 19),
      ),
      StaticPopupMenuButton(
        icon: const Icon(Icons.more_vert, size: 19),
        itemBuilder: (BuildContext context) => <PopupMenuEntry>[
          if (controller.commentType == 12)
            PopupMenuItem(
              onTap: controller.actionCoin,
              child: Obx(() {
                final color = controller.hasCoin
                    ? theme.colorScheme.primary
                    : null;
                return Row(
                  spacing: 10,
                  mainAxisSize: .min,
                  children: [
                    Icon(FontAwesomeIcons.b, size: 19, color: color),
                    Text('投币', style: TextStyle(color: color)),
                  ],
                );
              }),
            ),
          PopupMenuItem(
            onTap: () => ShareUtils.shareText(controller.url),
            child: const Row(
              spacing: 10,
              mainAxisSize: .min,
              children: [
                Icon(Icons.share_outlined, size: 19),
                Text('分享'),
              ],
            ),
          ),
          PopupMenuItem(
            onTap: () => Utils.copyText(controller.url),
            child: const Row(
              spacing: 10,
              mainAxisSize: .min,
              children: [
                Icon(Icons.copy_rounded, size: 19),
                Text('复制链接'),
              ],
            ),
          ),
          if (controller.commentType == 12 &&
              controller.stats.value != null &&
              controller.opusData?.modules.moduleBlocked == null)
            PopupMenuItem(
              onTap: () async {
                final summary = controller.summary;
                try {
                  if (summary.cover == null) {
                    if (!await controller.getArticleInfo(true)) {
                      return;
                    }
                  }
                  if (mounted) {
                    PageUtils.pmShare(
                      this.context,
                      content: {
                        "id": controller.commentId,
                        "title": "- 哔哩哔哩专栏",
                        "headline": summary.title!, // throw
                        "source": 6,
                        "thumb": summary.cover!,
                        "author": summary.author!.name,
                        "author_id": summary.author!.mid.toString(),
                      },
                    );
                  }
                } catch (e) {
                  SmartDialog.showToast(e.toString());
                }
              },
              child: const Row(
                spacing: 10,
                mainAxisSize: .min,
                children: [
                  Icon(Icons.forward_to_inbox, size: 19),
                  Text('分享至消息'),
                ],
              ),
            ),
        ],
      ),
      const SizedBox(width: 6),
    ],
  );

  Widget _buildBottom() {
    if (!controller.showDynActionBar) {
      return fabButton;
    }

    late final primary = theme.colorScheme.primary;
    late final outline = theme.colorScheme.outline;
    late final btnStyle = TextButton.styleFrom(
      tapTargetSize: .padded,
      padding: const .symmetric(horizontal: 15),
      foregroundColor: outline,
    );

    return Padding(
      padding: .only(left: padding.left, right: padding.right),
      child: Obx(() {
        final stats = controller.stats.value;

        final fab = Padding(
          padding: .only(
            right: kFloatingActionButtonMargin,
            bottom:
                kFloatingActionButtonMargin +
                (stats != null ? 0 : padding.bottom),
          ),
          child: replyButton,
        );

        if (stats == null) {
          return Align(alignment: .bottomRight, child: fab);
        }

        Widget textIconButton({
          required IconData icon,
          required String text,
          required DynamicStat? stat,
          required VoidCallback onPressed,
          IconData? activatedIcon,
        }) {
          final bool status;
          final String count;
          if (stat != null) {
            status = stat.status ?? false;
            count = stat.count != null ? NumUtils.numFormat(stat.count) : text;
          } else {
            status = false;
            count = text;
          }
          final color = status ? primary : outline;
          return TextButton.icon(
            style: btnStyle,
            onPressed: onPressed,
            label: Text(count, style: TextStyle(color: color)),
            icon: Icon(status ? activatedIcon : icon, size: 16, color: color),
          );
        }

        return Column(
          mainAxisSize: .min,
          crossAxisAlignment: .end,
          children: [
            fab,
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.08),
                  ),
                ),
              ),
              padding: .only(bottom: padding.bottom),
              child: Row(
                children: [
                  Expanded(
                    child: Builder(
                      builder: (btnContext) {
                        final forward = stats.forward;
                        return textIconButton(
                          text: '转发',
                          icon: FontAwesomeIcons.shareFromSquare,
                          stat: forward,
                          onPressed: () {
                            if (controller.opusData == null &&
                                controller.articleData?.dynIdStr == null) {
                              SmartDialog.showToast(
                                'err: ${controller.id}',
                              );
                              return;
                            }
                            final summary = controller.summary;
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              builder: (context) => RepostPanel(
                                item: controller.opusData,
                                dynIdStr: controller.articleData?.dynIdStr,
                                pic: summary.cover,
                                title: summary.title,
                                uname: summary.author?.name,
                                replyInfo: (
                                  oid: controller.oid,
                                  replyType: controller.replyType,
                                ),
                                mentionItem: summary.author?.mentionItem,
                                onSuccess: () {
                                  if (forward != null) {
                                    int count = forward.count ?? 0;
                                    forward.count = count + 1;
                                    if (btnContext.mounted) {
                                      (btnContext as Element?)
                                          ?.markNeedsBuild();
                                    }
                                  }
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  // Expanded(
                  //   child: textIconButton(
                  //     text: '分享',
                  //     icon: CustomIcons.share_node,
                  //     stat: null,
                  //     onPressed: () => ShareUtils.shareText(controller.url),
                  //   ),
                  // ),
                  Expanded(
                    child: textIconButton(
                      icon: FontAwesomeIcons.star,
                      activatedIcon: FontAwesomeIcons.solidStar,
                      text: '收藏',
                      stat: stats.favorite,
                      onPressed: controller.onFav,
                    ),
                  ),
                  Expanded(
                    child: textIconButton(
                      icon: FontAwesomeIcons.comment,
                      text: '评论',
                      stat: stats.comment,
                      onPressed: _jumpToComment,
                    ),
                  ),
                  Expanded(
                    child: textIconButton(
                      icon: FontAwesomeIcons.thumbsUp,
                      activatedIcon: FontAwesomeIcons.solidThumbsUp,
                      text: '点赞',
                      stat: stats.like,
                      onPressed: controller.onLike,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget? _buildImageGallery(List<Pic> pics) {
    final length = pics.length;
    final first = pics.first;
    double height;
    if (first.height != null && first.width != null) {
      final ratio = first.height! / first.width!;
      height = min(maxWidth * ratio, maxHeight * 0.55);
    } else {
      height = maxHeight * 0.55;
    }
    return Stack(
      clipBehavior: .none,
      children: [
        Container(
          height: height,
          width: maxWidth,
          margin: const .only(bottom: 10),
          child: PageView.builder(
            physics: tabBarScrollPhysics,
            horizontalDragGestureRecognizer:
                CustomHorizontalDragGestureRecognizer.new,
            onPageChanged: controller.topIndex.call,
            itemCount: length,
            itemBuilder: (context, index) {
              final pic = pics[index];
              int? memCacheWidth, memCacheHeight;
              if (pic.isLongPic ?? false) {
                memCacheWidth = maxWidth.cacheSize(context);
              } else if (pic.width != null && pic.height != null) {
                if (pic.width! > pic.height!) {
                  memCacheWidth = maxWidth.cacheSize(
                    context,
                  );
                } else {
                  memCacheHeight = height.cacheSize(
                    context,
                  );
                }
              }
              return GestureDetector(
                behavior: .opaque,
                onTap: () => PageUtils.imageView(
                  quality: 60,
                  imgList: pics.map((e) => SourceModel(url: e.url!)).toList(),
                  initialPage: index,
                ),
                child: Hero(
                  tag: pic.url!,
                  child: Stack(
                    clipBehavior: .none,
                    alignment: Alignment.center,
                    children: [
                      CachedNetworkImage(
                        height: height,
                        width: maxWidth,
                        gaplessPlayback: true,
                        memCacheWidth: memCacheWidth,
                        memCacheHeight: memCacheHeight,
                        fit: pic.isLongPic == true ? BoxFit.cover : null,
                        imageUrl: ImageUtils.thumbnailUrl(pic.url, 60),
                        fadeInDuration: const Duration(milliseconds: 120),
                        fadeOutDuration: const Duration(milliseconds: 120),
                        placeholder: (_, _) => const SizedBox.shrink(),
                      ),
                      if (pic.isLongPic == true)
                        const PBadge(
                          right: 12,
                          bottom: 12,
                          text: '长图',
                          type: .primary,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Obx(
          () => PBadge(
            top: 12,
            right: 12,
            type: .gray,
            text: '${controller.topIndex.value + 1}/$length',
          ),
        ),
      ],
    );
  }

  Widget? _buildAuthor() {
    final pubTime =
        controller.opusData?.modules.moduleAuthor?.pubTs ??
        controller.articleData?.publishTime;
    return Padding(
      padding: const .symmetric(vertical: 10),
      child: GestureDetector(
        onTap: () => Get.toNamed(
          '/member?mid=${controller.summary.author?.mid}',
        ),
        child: SelectionContainer.disabled(
          child: Row(
            spacing: 10,
            children: [
              NetworkImgLayer(
                width: 40,
                height: 40,
                type: .avatar,
                src: controller.summary.author?.face,
              ),
              Flexible(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      controller.summary.author?.name ?? '',
                      style: TextStyle(
                        fontSize: theme.textTheme.titleSmall!.fontSize,
                      ),
                    ),
                    if (pubTime != null)
                      Text(
                        DateFormatUtils.format(pubTime),
                        style: TextStyle(
                          color: theme.colorScheme.outline,
                          fontSize: theme.textTheme.labelSmall!.fontSize,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _jumpToComment() {
    if (!isPortrait) return;
    if (_centerKey == null) {
      _centerKey = UniqueKey();
      setState(() {});
    } else {
      PrimaryScrollController.of(context).jumpToTop();
    }
  }

  @override
  Widget httpError({String? errMsg, VoidCallback? onReload}) {
    return ArticleSliverToBoxAdapter(
      child: HttpError(
        isSliver: false,
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    );
  }
}
