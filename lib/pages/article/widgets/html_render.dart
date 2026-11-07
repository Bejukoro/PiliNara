import 'package:PiliPlus/pages/article/widgets/reading_settings.dart';
import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/widgets/image_viewer/hero.dart';
import 'package:PiliPlus/models/common/image_preview_type.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_html/flutter_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:material_ui/material_ui.dart';

class _ReadingContrastExtension extends HtmlExtension {
  const _ReadingContrastExtension(this.background);

  final Color background;

  @override
  Set<String> get supportedTags => const {};

  @override
  bool matches(ExtensionContext context) =>
      context.currentStep == CurrentStep.preProcessing &&
      identical(context.node, context.parser.htmlData);

  @override
  void beforeProcessing(ExtensionContext context) {
    final foreground = Theme.of(context.buildContext!).colorScheme.onSurface;
    void adjust(StyledElement element, Color inheritedBackground) {
      final effectiveBackground = Color.alphaBlend(
        element.style.backgroundColor ?? Colors.transparent,
        inheritedBackground,
      );
      element.style.color = ArticleReadingSettings.readableOn(
        effectiveBackground,
        element.style.color ?? foreground,
      );
      for (final child in element.children) {
        adjust(child, effectiveBackground);
      }
    }

    adjust(context.styledElement!, background);
  }
}

Widget htmlRender({
  required BuildContext context,
  dom.Element? element,
  String? html,
  int? imgCount,
  List<String>? imgList,
  required double maxWidth,
  Color? readingBackground,
  ArticleReadingSettings readingSettings = const ArticleReadingSettings(),
}) {
  // if (kDebugMode) debugPrint('htmlRender');
  final extensions = [
    if (readingBackground != null) _ReadingContrastExtension(readingBackground),
    TagExtension(
      tagsToExtend: <String>{'img'},
      builder: (ExtensionContext extensionContext) {
        try {
          final Map<String, dynamic> attributes = extensionContext.attributes;
          final List<dynamic> key = attributes.keys.toList();
          String imgUrl = key.contains('src')
              ? attributes['src'] as String
              : attributes['data-src'] as String;
          imgUrl = imgUrl.contains('@') ? imgUrl.split('@').first : imgUrl;
          final bool isEmote = imgUrl.contains('/emote/');
          final bool isMall = imgUrl.contains('/mall/');
          if (isMall) {
            return const SizedBox.shrink();
          }

          String? clazz = attributes['class'];
          String? height = RegExp(
            r'max-height:(\d+)px',
          ).firstMatch('${attributes['style']}')?.group(1);
          if (clazz?.contains('cut-off') == true || height != null) {
            return CachedNetworkImage(
              width: maxWidth,
              gaplessPlayback: true,
              memCacheWidth: maxWidth.cacheSize(context),
              height: height != null ? double.parse(height) : null,
              imageUrl: ImageUtils.thumbnailUrl(imgUrl),
              fit: BoxFit.contain,
              placeholder: (_, _) => const SizedBox.shrink(),
            );
          }
          final width = isEmote ? 22.0 : maxWidth;
          return GestureDetector(
            onTap: () => PageUtils.imageView(
              imgList: [SourceModel(url: imgUrl)],
              quality: 60,
            ),
            child: fromHero(
              tag: imgUrl,
              child: CachedNetworkImage(
                width: width,
                gaplessPlayback: true,
                height: isEmote ? 22.0 : null,
                memCacheWidth: width.cacheSize(context),
                imageUrl: ImageUtils.thumbnailUrl(imgUrl, 60),
                fadeInDuration: const Duration(milliseconds: 120),
                fadeOutDuration: const Duration(milliseconds: 120),
                placeholder: (context, url) => Image.asset(Assets.loading),
              ),
            ),
          );
        } catch (err) {
          if (kDebugMode) debugPrint('错误的HTML: $element');
          return const SizedBox.shrink();
        }
      },
    ),
  ];
  final style = {
    'html': Style(
      fontSize: FontSize(readingSettings.fontSize),
      lineHeight: LineHeight.percent(readingSettings.lineHeight * 100),
      fontFamily: readingSettings.fontFamily,
      letterSpacing: 0.3,
    ),
    '*': Style(
      fontFamily: readingSettings.fontFamily,
      lineHeight: LineHeight.percent(readingSettings.lineHeight * 100),
    ),
    'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
    'a': Style(
      color: Theme.of(context).colorScheme.primary,
      textDecoration: TextDecoration.none,
    ),
    'br': Style(
      lineHeight: LineHeight.percent(-1),
    ),
    'p': Style(
      margin: Margins.only(
        bottom: element?.localName == 'p'
            ? 0
            : readingSettings.paragraphSpacing,
      ),
    ),
    'span': Style(fontSize: FontSize(readingSettings.fontSize)),
    'div': Style(height: Height.auto()),
    'li > p': Style(
      display: Display.inline,
    ),
    'li': Style(
      padding: HtmlPaddings.only(bottom: 4),
      textAlign: TextAlign.justify,
    ),
    'img': Style(margin: Margins.only(top: 4, bottom: 4)),
    'h1,h2': Style(
      fontSize: FontSize(readingSettings.fontSize * 1.4),
      fontWeight: FontWeight.bold,
      margin: Margins.only(bottom: 8),
    ),
    'h3,h4,h5': Style(
      fontSize: FontSize(readingSettings.fontSize),
      fontWeight: FontWeight.bold,
      margin: Margins.only(bottom: 4),
    ),
    'figcaption': Style(
      fontSize: FontSize(readingSettings.fontSize),
      textAlign: TextAlign.center,
    ),
    'strong': Style(fontWeight: FontWeight.bold),
    'figure': Style(
      margin: Margins.zero,
    ),
  };
  return element != null
      ? Html.fromElement(
          documentElement: element,
          extensions: extensions,
          style: style,
        )
      : Html(
          data: html,
          extensions: extensions,
          style: style,
        );
}
