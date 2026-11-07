import 'package:PiliPlus/models/dynamics/article_content_model.dart';
import 'package:PiliPlus/models_new/article/article_view/ops.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

List<String> articleSpeechChunks({
  String? title,
  List<ArticleContentModel>? opus,
  List<ArticleOps>? ops,
  String? content,
}) {
  String nodeText(Node node) {
    if (node.word != null) return node.word?.words ?? '';
    final rich = node.rich;
    return rich?.type == null || rich?.type == 'RICH_TEXT_NODE_TYPE_TEXT'
        ? rich?.text ?? ''
        : '';
  }

  Iterable<String> nodes(Text? text) => text?.nodes?.map(nodeText) ?? const [];
  Iterable<String> paragraphs(ArticleContentModel item) sync* {
    yield nodes(item.heading).join();
    yield nodes(item.text).join();
    for (final child in item.blockquote?.children ?? <ArticleContentModel>[]) {
      yield* paragraphs(child);
    }
    for (final entry in item.list?.items ?? <Item>[]) {
      yield entry.nodes?.map(nodeText).join() ?? '';
    }
    for (final entry in item.list?.children ?? <Child>[]) {
      for (final child in entry.children ?? <ArticleContentModel>[]) {
        yield* paragraphs(child);
      }
    }
  }

  final blocks = <String>[];
  if (opus != null && opus.isNotEmpty) {
    for (final item in opus) {
      blocks.addAll(paragraphs(item));
    }
  } else if (ops != null && ops.isNotEmpty) {
    final content = StringBuffer();
    for (final item in ops) {
      final classes =
          item.attributes?.clazz?.split(RegExp(r'\s+')) ?? const <String>[];
      if (item.insert is String && !classes.any(_metadataClasses.contains)) {
        content.write(item.insert as String);
      }
    }
    blocks.addAll(content.toString().split('\n'));
  } else if (content != null) {
    blocks.addAll(_htmlText(html.parse(content).body!).join().split('\n'));
  }
  final body = <String>[];
  var atBeginning = true;
  final metadataField = RegExp(
    r'^(?:tags?|标签|话题|作者|发布时间|发布日期|更新时间|分类|文集|文章标题|标题)\s*[:：]',
    caseSensitive: false,
  );
  for (final block in blocks) {
    final lines = <String>[];
    for (final line in block.split('\n')) {
      final text = line.trim();
      if (text.isEmpty || metadataField.hasMatch(text)) continue;
      if (atBeginning && title != null && text == title.trim()) continue;
      atBeginning = false;
      lines.add(line);
    }
    if (lines.isNotEmpty) body.add(lines.join('\n'));
  }
  return splitSpeechChunks(body);
}

const _metadataClasses = {
  'article-title',
  'article-tags',
  'tag-list',
  'tags',
  'topic-tag',
  'article-author',
  'author-info',
  'publish-time',
  'article-time',
};

Iterable<String> _htmlText(dom.Node node) sync* {
  if (node is dom.Element) {
    final link = Uri.tryParse(node.attributes['href'] ?? '');
    if (node.classes.any(_metadataClasses.contains) ||
        link?.queryParameters.containsKey('topic_id') == true ||
        link?.path.contains('topic-detail') == true) {
      return;
    }
  }
  if (node is dom.Element &&
      const {
        'title',
        'header',
        'footer',
        'nav',
        'script',
        'style',
        'iframe',
        'noscript',
        'pre',
        'code',
      }.contains(node.localName)) {
    return;
  }
  if (node is dom.Text) {
    yield node.text;
    return;
  }
  for (final child in node.nodes) {
    yield* _htmlText(child);
    if (child is dom.Element &&
        const {
          'p',
          'div',
          'li',
          'br',
          'h1',
          'h2',
          'h3',
          'blockquote',
        }.contains(child.localName)) {
      yield '\n';
    }
  }
}

/// Keep paragraph boundaries while joining short consecutive paragraphs.
List<String> splitSpeechChunks(Iterable<String> blocks, {int minimum = 10}) {
  if (minimum < 0) throw ArgumentError.value(minimum, 'minimum');
  final chunks = <String>[];
  final pending = <String>[];
  var characters = 0;
  for (final block in blocks) {
    final text = block.replaceAll(RegExp(r'[ \t\r]+'), ' ').trim();
    if (text.isEmpty) continue;
    pending.add(text);
    characters += text.runes.length;
    if (characters > minimum) {
      chunks.add(pending.join('\n'));
      pending.clear();
      characters = 0;
    }
  }
  if (pending.isNotEmpty) {
    if (chunks.isEmpty) {
      chunks.add(pending.join('\n'));
    } else {
      chunks[chunks.length - 1] += '\n${pending.join('\n')}';
    }
  }
  return chunks;
}

class SpeechPlaybackPlan {
  const SpeechPlaybackPlan(this.chunks, this.paragraphIndexes);
  final List<String> chunks;
  final List<int> paragraphIndexes;
}

SpeechPlaybackPlan articleSpeechPlaybackPlan(
  List<String> paragraphs, {
  int limit = 450,
}) {
  if (limit < 1) throw ArgumentError.value(limit, 'limit');
  final chunks = <String>[];
  final indexes = <int>[];
  for (var paragraph = 0; paragraph < paragraphs.length; paragraph++) {
    final runes = paragraphs[paragraph].runes.toList();
    var start = 0;
    while (start < runes.length) {
      var end = (start + limit).clamp(0, runes.length);
      if (end < runes.length) {
        for (var i = end - 1; i > start + limit ~/ 2; i--) {
          if ('。！？；.!?\n'.runes.contains(runes[i])) {
            end = i + 1;
            break;
          }
        }
      }
      final text = String.fromCharCodes(runes.sublist(start, end)).trim();
      if (text.isNotEmpty) {
        chunks.add(text);
        indexes.add(paragraph);
      }
      start = end;
    }
  }
  return SpeechPlaybackPlan(chunks, indexes);
}

/// Microsoft demo requests are larger to reduce request frequency.
SpeechPlaybackPlan microsoftSpeechPlaybackPlan(
  List<String> paragraphs, {
  int target = 450,
}) {
  if (target < 1) throw ArgumentError.value(target, 'target');
  final chunks = <String>[];
  final indexes = <int>[];
  final current = <String>[];
  var count = 0;
  for (var i = 0; i < paragraphs.length; i++) {
    if (current.isEmpty) indexes.add(i);
    current.add(paragraphs[i]);
    count += paragraphs[i].runes.length;
    if (count >= target) {
      chunks.add(current.join('\n'));
      current.clear();
      count = 0;
    }
  }
  if (current.isNotEmpty) chunks.add(current.join('\n'));
  return SpeechPlaybackPlan(chunks, indexes);
}
