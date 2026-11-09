import 'dart:io';

import 'package:PiliPlus/pages/article/listen/settings.dart';
import 'package:PiliPlus/pages/article/listen/speech_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late ArticleSpeechCache cache;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'article-speech-cache-test-',
    );
    cache = ArticleSpeechCache(
      directory: Directory('${temporary.path}/cache'),
      limitMb: () => 200,
    );
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('cache identity changes for output settings but not playback speed or credentials', () {
    final settings = ArticleSpeechSettings()
      ..provider = SpeechProvider.qwen
      ..credentials = {'qwenKey': 'secret-test-key'};
    final key = ArticleSpeechCache.keyFor('正文', settings);
    settings
      ..rate = 1.5
      ..credentials = {'qwenKey': 'another-test-key'};
    expect(ArticleSpeechCache.keyFor('正文', settings), key);
    expect(key, matches(RegExp(r'^[a-f0-9]{64}$')));
    settings.qwenVoice = 'other-voice';
    expect(ArticleSpeechCache.keyFor('正文', settings), isNot(key));
    expect(ArticleSpeechCache.keyFor('另一段', settings), isNot(key));
  });

  test('cached audio survives cache instances and clear leaves the playback copy intact', () async {
    final settings = ArticleSpeechSettings()
      ..provider = SpeechProvider.microsoftDemo;
    final key = ArticleSpeechCache.keyFor('完整段落', settings);
    final source = await File('${temporary.path}/source.mp3')
        .writeAsBytes([1, 2, 3]);
    await cache.store(key, 'mp3', source);
    final reopened = ArticleSpeechCache(
      directory: cache.directory,
      limitMb: () => 200,
    );
    final restored = await reopened.restore(
      key,
      'mp3',
      '${temporary.path}/playback.mp3',
    );
    expect(await restored!.readAsBytes(), [1, 2, 3]);
    expect(await reopened.sizeBytes(), 3);
    await reopened.clear();
    expect(await reopened.sizeBytes(), 0);
    expect(await restored.readAsBytes(), [1, 2, 3]);
    expect(
      await reopened.restore(key, 'mp3', '${temporary.path}/missing.mp3'),
      isNull,
    );
  });
}
