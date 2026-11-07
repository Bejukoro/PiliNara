import 'dart:convert';

import 'package:PiliPlus/pages/article/listen/voice.dart';

import 'package:PiliPlus/utils/storage.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;

class QwenVoiceCatalog {
  static const source =
      'https://help.aliyun.com/zh/model-studio/qwen-audio-tts-voice-list';
  static const _cacheKey = 'articleSpeechQwenCatalog';

  static List<SpeechVoice> cached() {
    try {
      final data = GStorage.setting.get(_cacheKey) as Map?;
      return (data?['voices'] as List? ?? [])
          .map((e) => SpeechVoice.fromJson(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<SpeechVoice>> fetch() async {
    final http = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    try {
      final response = await http.get<String>(source);
      final voices = parse(response.data ?? '');
      if (voices.isEmpty) throw StateError('官方音色目录格式已变化，请使用手动填写');
      await GStorage.setting.put(_cacheKey, {
        'voices': voices.map((e) => e.toJson()).toList(),
      });
      return voices;
    } finally {
      http.close();
    }
  }

  static List<SpeechVoice> parse(String page) {
    // The official page embeds its article HTML in SSR JSON.
    final embedded = RegExp(r'"content":("(?:\\.|[^"\\])*")').firstMatch(page);
    final content = embedded == null
        ? page
        : jsonDecode(embedded.group(1)!) as String;
    final document = html.parse(content);
    final result = <String, SpeechVoice>{};
    String? model;
    String text(String markup) => html
        .parse(
          markup
              .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
              .replaceAll('</p>', '\n'),
        )
        .body!
        .text
        .trim();
    String attribute(String value, String label) =>
        RegExp('(?:$label)\\s*[:：]\\s*([^\\n]+)')
            .firstMatch(value)
            ?.group(1)
            ?.trim() ??
        '';
    for (final element in document.querySelectorAll('h2, h3, table')) {
      if (element.localName != 'table') {
        model = RegExp(r'qwen-audio-\d+\.\d+-tts-(?:plus|flash)')
            .firstMatch(element.text)
            ?.group(0);
        continue;
      }
      if (model == null) continue;
      final headers = element
          .querySelectorAll('thead th')
          .map((e) => e.text.trim())
          .toList();
      for (final row in element.querySelectorAll('tbody > tr')) {
        final cells = row.children.where((e) => e.localName == 'td').toList();
        if (cells.isEmpty) continue;
        final infoCell = cells
            .where((e) => RegExp(r'voice\s*参数').hasMatch(e.text))
            .firstOrNull;
        if (infoCell == null) continue;
        final info = text(infoCell.innerHtml);
        final id =
            infoCell.querySelector('code')?.text.trim() ??
            attribute(info, r'voice\s*参数');
        if (id.isEmpty || !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(id)) continue;
        String column(String pattern) {
          final index = headers.indexWhere((e) => RegExp(pattern).hasMatch(e));
          return index >= 0 && index < cells.length
              ? text(cells[index].innerHtml)
              : '';
        }

        final name = attribute(info, '音色名称|名称');
        final gender = column('性别');
        final style = column('特点|风格|特征|特质');
        final age = column('年龄');
        final voice = SpeechVoice(
          model: model,
          id: id,
          name: name.isEmpty ? id : name,
          gender: gender.isEmpty ? attribute(info, '性别') : gender,
          style: style.isEmpty ? attribute(info, '特点|风格|特征|特质') : style,
          age: age.isEmpty ? attribute(info, '年龄') : age,
        );
        result['$model/$id'] = voice;
      }
    }
    return result.values.toList();
  }
}
