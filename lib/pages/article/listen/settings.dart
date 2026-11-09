import 'dart:convert';

import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum SpeechProvider {
  system('系统 TTS'),
  qwen('千问'),
  microsoftDemo('微软演示');

  const SpeechProvider(this.label);
  final String label;
}

class ArticleSpeechSettings {
  static const defaultQwenPrefetchParagraphs = 5;
  static const maxQwenPrefetchParagraphs = 15;
  SpeechProvider provider = SpeechProvider.system;
  String systemEngine = '';
  String systemVoice = '';
  String systemLocale = 'zh-CN';
  String microsoftVoice = 'zh-CN-YunjianNeural';
  String microsoftLocale = 'zh-CN';
  String qwenVoice = 'longzhe_v3.1';
  String qwenModel = 'qwen-audio-3.1-tts-flash';
  int qwenPrefetchParagraphs = defaultQwenPrefetchParagraphs;
  String qwenEndpoint =
      'wss://cn-beijing.maas.qianwenaiapi.com/api-ws/v1/inference';
  double rate = 1;
  Map<String, String> credentials = {};
  String? credentialsError;
  static const _secure = FlutterSecureStorage();
  static const _key = 'articleSpeechSettings';

  static Future<ArticleSpeechSettings> load() async {
    final result = ArticleSpeechSettings();
    final data = GStorage.setting.get(_key);
    if (data is Map) {
      result
        ..provider = SpeechProvider.values.firstWhere(
          (e) => e.name == data['provider'],
          orElse: () => SpeechProvider.system,
        )
        ..systemEngine = data['systemEngine'] as String? ?? ''
        ..systemVoice = data['systemVoice'] as String? ?? ''
        ..systemLocale = data['systemLocale'] as String? ?? 'zh-CN'
        ..microsoftVoice =
            data['microsoftVoice'] as String? ?? result.microsoftVoice
        ..microsoftLocale =
            data['microsoftLocale'] as String? ?? result.microsoftLocale
        ..qwenVoice = data['qwenVoice'] as String? ?? result.qwenVoice
        ..qwenModel = data['qwenModel'] as String? ?? result.qwenModel
        ..qwenEndpoint = data['qwenEndpoint'] as String? ?? result.qwenEndpoint;
      if (result.microsoftVoice == 'zh-CN-XiaoxiaoNeural') {
        result.microsoftVoice = 'zh-CN-YunjianNeural';
      }
      if (result.qwenEndpoint ==
              'https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation' &&
          result.qwenModel == 'qwen3-tts-flash' &&
          result.qwenVoice == 'Cherry') {
        final defaults = ArticleSpeechSettings();
        result
          ..qwenEndpoint = defaults.qwenEndpoint
          ..qwenModel = defaults.qwenModel
          ..qwenVoice = defaults.qwenVoice;
      }
      if (result.qwenModel == 'qwen-audio-3.1-tts-flash' &&
          result.qwenVoice == 'longanhuan_v3.1') {
        result.qwenVoice = 'longzhe_v3.1';
      }
      if (data['qwenPrefetchParagraphs'] case final num count
          when count.isFinite) {
        result.qwenPrefetchParagraphs = count.toInt().clamp(
          0,
          maxQwenPrefetchParagraphs,
        );
      }
      if (data['rate'] case final num rate when rate.isFinite) {
        result.rate = rate.toDouble().clamp(.5, 2);
      }
    }
    try {
      final secret = await _secure
          .read(key: _key)
          .timeout(const Duration(seconds: 5));
      if (secret != null) {
        result.credentials = Map<String, String>.from(
          jsonDecode(secret) as Map,
        )..removeWhere((key, _) => key != 'qwenKey');
      }
    } catch (_) {
      result.credentialsError = '千问凭据读取失败，请重试安全存储后再配置千问';
    }
    return result;
  }

  Future<void> save() async {
    if (credentialsError != null && provider == SpeechProvider.qwen) {
      throw StateError(credentialsError!);
    }
    if (credentialsError == null) {
      await _secure
          .write(
            key: _key,
            value: jsonEncode(
              Map<String, String>.from(credentials)
                ..removeWhere((key, _) => key != 'qwenKey'),
            ),
          )
          .timeout(const Duration(seconds: 8));
    }
    await GStorage.setting.put(_key, {
      'provider': provider.name,
      'systemEngine': systemEngine,
      'systemVoice': systemVoice,
      'systemLocale': systemLocale,
      'microsoftVoice': microsoftVoice,
      'microsoftLocale': microsoftLocale,
      'qwenVoice': qwenVoice,
      'qwenModel': qwenModel,
      'qwenEndpoint': qwenEndpoint,
      'qwenPrefetchParagraphs': qwenPrefetchParagraphs.clamp(
        0,
        maxQwenPrefetchParagraphs,
      ),
      'rate': rate,
    });
  }
}
