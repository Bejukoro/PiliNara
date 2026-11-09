// Async file operations keep cache maintenance off the UI thread.
// ignore_for_file: avoid_slow_async_io

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/pages/article/listen/settings.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

/// Persistent synthesized audio only; credentials and article text are never
/// stored in filenames or alongside cached files.
class ArticleSpeechCache {
  ArticleSpeechCache({Directory? directory, int Function()? limitMb})
    : directory =
          directory ??
          Directory(path.join(appSupportDirPath, 'article_speech_cache')),
      _limitMb = limitMb ?? configuredLimitMb;

  static const minLimitMb = 200;
  static const maxLimitMb = 2048;
  static const defaultLimitMb = 512;
  static const _bytesPerMb = 1024 * 1024;
  static Future<void> _tail = Future.value();
  static final _knownSizes = <String, int>{};
  final Directory directory;
  final int Function() _limitMb;

  static int configuredLimitMb() {
    final value = GStorage.setting.get(SettingBoxKey.articleSpeechCacheLimitMb);
    return (value is num && value.isFinite ? value.toInt() : defaultLimitMb)
        .clamp(
          minLimitMb,
          maxLimitMb,
        );
  }

  static String keyFor(
    String text,
    ArticleSpeechSettings settings, {
    String? systemEngine,
    String? systemVoice,
  }) {
    final identity = switch (settings.provider) {
      SpeechProvider.system => [
        'system',
        systemEngine,
        systemVoice,
        settings.systemLocale,
      ],
      SpeechProvider.qwen => [
        'qwen-pcm-v1',
        settings.qwenEndpoint.trim(),
        settings.qwenModel.trim(),
        settings.qwenVoice.trim(),
      ],
      SpeechProvider.microsoftDemo => [
        'microsoft-demo-v1',
        settings.microsoftLocale.trim(),
        settings.microsoftVoice.trim(),
      ],
    };
    return sha256.convert(utf8.encode(jsonEncode([identity, text]))).toString();
  }

  Future<T> _locked<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, trace) {
        result.completeError(error, trace);
      }
    });
    return result.future;
  }

  File _file(String key, String extension) =>
      File(path.join(directory.path, '$key.$extension'));

  /// Copies to the current playback session, keeping the persistent copy safe
  /// from player cleanup and allowing users to clear it while audio is open.
  Future<File?> restore(String key, String extension, String destination) =>
      _locked(() async {
        final file = _file(key, extension);
        if (!await file.exists()) return null;
        if (await file.length() == 0) {
          await file.delete();
          return null;
        }
        final copy = await file.copy(destination);
        try {
          await file.setLastModified(DateTime.now());
        } on FileSystemException {
          // A timestamp failure does not prevent reuse of valid audio.
        }
        return copy;
      });

  Future<void> store(String key, String extension, File source) => _locked(
    () async {
      final size = await source.length();
      final limit = _limitMb().clamp(minLimitMb, maxLimitMb) * _bytesPerMb;
      if (size <= 0 || size > limit) return;
      await directory.create(recursive: true);
      final target = _file(key, extension);
      if (await target.exists() && await target.length() > 0) {
        await target.setLastModified(DateTime.now());
        return;
      }
      final knownSize =
          _knownSizes[directory.path] ??
          (await _entries()).fold<int>(0, (sum, entry) => sum + entry.$2.size);
      final temporary = await File(path.join(directory.path, '$key.part'))
          .create();
      try {
        await source.copy(temporary.path);
        if (await target.exists()) await target.delete();
        await temporary.rename(target.path);
        _knownSizes[directory.path] = knownSize + size;
        if (_knownSizes[directory.path]! > limit) await _prune(limit);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    },
  );

  Future<List<(File, FileStat)>> _entries() async {
    if (!await directory.exists()) return [];
    final files = <(File, FileStat)>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File &&
          RegExp(r'^[a-f0-9]{64}\.part$').hasMatch(path.basename(entry.path))) {
        try {
          await entry.delete();
        } on FileSystemException {
          /* Removed externally. */
        }
        continue;
      }
      if (entry is File &&
          RegExp(r'^[a-f0-9]{64}\.(wav|mp3)$')
              .hasMatch(path.basename(entry.path))) {
        try {
          files.add((entry, await entry.stat()));
        } on FileSystemException {
          /* Removed externally. */
        }
      }
    }
    return files;
  }

  Future<int> sizeBytes() => _locked(() async {
    final entries = await _entries();
    final size = entries.fold<int>(0, (sum, entry) => sum + entry.$2.size);
    _knownSizes[directory.path] = size;
    return size;
  });

  Future<void> enforceLimit() => _locked(
    () => _prune(_limitMb().clamp(minLimitMb, maxLimitMb) * _bytesPerMb),
  );

  Future<void> _prune(int limit) async {
    final entries = await _entries();
    var size = entries.fold<int>(0, (sum, entry) => sum + entry.$2.size);
    if (size <= limit) {
      _knownSizes[directory.path] = size;
      return;
    }
    entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final entry in entries) {
      if (size <= limit) break;
      try {
        await entry.$1.delete();
        size -= entry.$2.size;
      } on FileSystemException {
        /* Removed externally. */
      }
    }
    _knownSizes[directory.path] = size;
  }

  Future<void> clear() => _locked(() async {
    for (final entry in await _entries()) {
      try {
        await entry.$1.delete();
      } on FileSystemException {
        if (await entry.$1.exists()) rethrow;
      }
    }
    _knownSizes[directory.path] = 0;
  });
}
