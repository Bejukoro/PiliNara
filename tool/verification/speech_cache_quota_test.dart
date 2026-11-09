import 'dart:io';
import 'package:PiliPlus/pages/article/listen/speech_cache.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
 test('quota evicts the least recently used audio and preserves newer entries', () async {
  final root = await Directory.systemTemp.createTemp('tts-quota-');
  final cache = ArticleSpeechCache(directory: root, limitMb: () => 200);
  try {
   final oldFile = File('${root.path}/${'a' * 64}.wav');
   final newFile = File('${root.path}/${'b' * 64}.wav');
   for (final file in [oldFile,newFile]) { final handle = await file.open(mode: FileMode.write); await handle.truncate(105 * 1024 * 1024); await handle.close(); }
   await oldFile.setLastModified(DateTime(2020)); await newFile.setLastModified(DateTime(2021));
   await cache.enforceLimit();
   expect(await oldFile.exists(), isFalse);
   expect(await newFile.exists(), isTrue);
   expect(await cache.sizeBytes(), 105 * 1024 * 1024);
  } finally { await root.delete(recursive: true); }
 });
}
