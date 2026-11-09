import 'package:PiliPlus/pages/article/listen/voice.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:dio/dio.dart';

class MicrosoftDemoCatalog {
  static const _key = SettingBoxKey.articleSpeechMicrosoftDemoCatalog;
  static List<SpeechVoice> cached() {
    try {
      return (GStorage.setting.get(_key) as List? ?? [])
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
      final response = await http.get<List<dynamic>>(
        'https://eastus.api.speech.microsoft.com/cognitiveservices/voices/list',
        options: Options(
          headers: {
            'Origin': 'https://azure.microsoft.com',
            'Referer': 'https://azure.microsoft.com',
            'X-Ms-Useragent': 'SpeechStudio/2021.05.001',
          },
        ),
      );
      final voices = parse(response.data ?? []);
      if (voices.isEmpty) throw StateError('微软演示未返回音色目录');
      await GStorage.setting.put(_key, voices.map((e) => e.toJson()).toList());
      return voices;
    } finally {
      http.close();
    }
  }

  static List<SpeechVoice> parse(List<dynamic> data) => [
    for (final entry in data.whereType<Map>())
      if (entry['ShortName'] is String && entry['Locale'] is String)
        SpeechVoice(
          model: 'microsoft-demo',
          id: entry['ShortName'] as String,
          name:
              entry['LocalName'] as String? ??
              entry['DisplayName'] as String? ??
              entry['ShortName'] as String,
          locale: entry['Locale'] as String,
          gender: switch (entry['Gender']) {
            'Female' => '女',
            'Male' => '男',
            _ => entry['Gender'] as String? ?? '',
          },
          style: (entry['StyleList'] as List? ?? []).whereType<String>().join(
            '、',
          ),
          age: '',
        ),
  ];
}
