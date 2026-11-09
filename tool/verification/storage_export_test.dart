import 'dart:convert';
import 'dart:typed_data';

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GStorage.setting = await Hive.openBox('setting', bytes: Uint8List(0));
    GStorage.video = await Hive.openBox('video', bytes: Uint8List(0));
    GStorage.localCache = await Hive.openBox('localCache', bytes: Uint8List(0));
  });

  tearDownAll(() async {
    await GStorage.setting.close();
    await GStorage.video.close();
    await GStorage.localCache.close();
  });

  test(
    'exports voice selections but excludes generated voice catalogs',
    () async {
      final selection = {'provider': 'qwen', 'qwenVoice': 'longzhe_v3.1'};
      final catalog = List.generate(1000, (i) => {'id': 'voice-$i'});
      await GStorage.setting.put('articleSpeechSettings', selection);
      await GStorage.setting.put(SettingBoxKey.articleSpeechQwenCatalog, {
        'voices': catalog,
      });
      await GStorage.setting.put(
        SettingBoxKey.articleSpeechMicrosoftDemoCatalog,
        catalog,
      );
      await GStorage.video.put('volume', 75);
      await GStorage.localCache.put('blackMids', [1, 2]);

      final data =
          jsonDecode(GStorage.exportAllSettings()) as Map<String, dynamic>;
      final settings = data['setting'] as Map<String, dynamic>;
      expect(settings['articleSpeechSettings'], selection);
      expect(settings, isNot(contains(SettingBoxKey.articleSpeechQwenCatalog)));
      expect(
        settings,
        isNot(contains(SettingBoxKey.articleSpeechMicrosoftDemoCatalog)),
      );
      expect((data['video'] as Map)['volume'], 75);
      expect((data[GStorage.localCache.name] as Map)['blackMids'], [1, 2]);
      expect(
        GStorage.setting.get(SettingBoxKey.articleSpeechQwenCatalog),
        isNotNull,
      );
      expect(
        GStorage.setting.get(SettingBoxKey.articleSpeechMicrosoftDemoCatalog),
        isNotNull,
      );
    },
  );

  test('imports old backups without restoring cached catalogs', () async {
    await GStorage.importAllJsonSettings({
      'setting': {
        'articleSpeechSettings': {
          'provider': 'microsoftDemo',
          'microsoftVoice': 'zh-CN-YunjianNeural',
        },
        SettingBoxKey.articleSpeechQwenCatalog: {
          'voices': [
            {'id': 'stale'},
          ],
        },
        SettingBoxKey.articleSpeechMicrosoftDemoCatalog: [
          {'id': 'stale'},
        ],
      },
      'video': {'volume': 50},
    });
    expect(
      GStorage.setting.get('articleSpeechSettings')['microsoftVoice'],
      'zh-CN-YunjianNeural',
    );
    expect(
      GStorage.setting.containsKey(SettingBoxKey.articleSpeechQwenCatalog),
      isFalse,
    );
    expect(
      GStorage.setting.containsKey(
        SettingBoxKey.articleSpeechMicrosoftDemoCatalog,
      ),
      isFalse,
    );
    expect(GStorage.video.get('volume'), 50);
  });
}
