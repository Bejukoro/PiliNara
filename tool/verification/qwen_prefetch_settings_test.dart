// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:typed_data';

import 'package:PiliPlus/pages/article/listen/settings.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GStorage.setting = await Hive.openBox('qwen-prefetch', bytes: Uint8List(0));
  });
  setUp(() async {
    await GStorage.setting.clear();
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDownAll(() => GStorage.setting.close());

  test('prefetch defaults to five and persists a selected value', () async {
    expect((await ArticleSpeechSettings.load()).qwenPrefetchParagraphs, 5);
    final settings = ArticleSpeechSettings()..qwenPrefetchParagraphs = 15;
    await settings.save();
    expect((await ArticleSpeechSettings.load()).qwenPrefetchParagraphs, 15);
  });

  test(
    'imported prefetch values are constrained to the supported range',
    () async {
      await GStorage.setting.put('articleSpeechSettings', {
        'qwenPrefetchParagraphs': 99,
      });
      expect((await ArticleSpeechSettings.load()).qwenPrefetchParagraphs, 15);
      await GStorage.setting.put('articleSpeechSettings', {
        'qwenPrefetchParagraphs': -1,
      });
      expect((await ArticleSpeechSettings.load()).qwenPrefetchParagraphs, 0);
    },
  );
}
