import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:PiliPlus/pages/article/listen/settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter_tts/flutter_tts.dart';

class ArticleSynthesizer {
  ArticleSynthesizer({
    Dio? http,
    Future<WebSocket> Function(Uri, Map<String, String>)? connectWebSocket,
  }) : _connectWebSocket =
           connectWebSocket ??
           ((uri, headers) =>
               WebSocket.connect(uri.toString(), headers: headers)),
       _http =
           http ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 60),
               sendTimeout: const Duration(seconds: 15),
             ),
           );
  final Future<WebSocket> Function(Uri, Map<String, String>) _connectWebSocket;
  final FlutterTts system = FlutterTts();
  final Dio _http;
  CancelToken? _cancel;
  WebSocket? _socket;
  int _generation = 0;
  Completer<void>? _cancelSignal;
  bool _usingSystem = false;
  String? _configuredEngine;

  Future<void> useSystemEngine(String engine) async {
    if (_configuredEngine == engine) return;
    await system.setEngine(engine);
    _configuredEngine = engine;
  }

  Future<void> cancel() async {
    _generation++;
    final signal = _cancelSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
    _cancel?.cancel();
    await _socket?.close().timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );
    _socket = null;
    if (_usingSystem) {
      try {
        await system.stop().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
  }

  Future<File> synthesize(
    String text,
    ArticleSpeechSettings settings,
    String path, {
    void Function(String)? onStatus,
    String? resolvedSystemEngine,
    String? resolvedSystemVoice,
  }) async {
    final generation = _generation;
    final cancelled = _cancelSignal = Completer<void>();
    _usingSystem = settings.provider == SpeechProvider.system;
    _cancel = CancelToken();
    final file = File(path);
    try {
      switch (settings.provider) {
        case SpeechProvider.system:
          onStatus?.call('正在初始化系统语音引擎');
          await _configureSystem(
            settings,
            cancelled.future,
            resolvedEngine: resolvedSystemEngine,
            resolvedVoice: resolvedSystemVoice,
          );
          // Android error callbacks do not resolve awaitSynthCompletion's
          // method result. Observe events explicitly so failures release the queue.
          final completion = Completer<void>();
          system.setCompletionHandler(() {
            if (!completion.isCompleted) completion.complete();
          });
          system.setErrorHandler((message) {
            if (!completion.isCompleted) {
              completion.completeError(
                StateError('系统 TTS 合成失败（$message），请在语音设置中试听并检查语音数据'),
              );
            }
          });
          system.setCancelHandler(() {
            if (!completion.isCompleted) {
              completion.completeError(StateError('系统 TTS 已取消合成'));
            }
          });
          // Attach the error listener before dispatching the native request.
          final finished = _systemCall(
            completion.future,
            cancelled.future,
            seconds: 60,
          );
          unawaited(finished.catchError((Object _) {}));
          try {
            await _systemCall(
              system.awaitSynthCompletion(false),
              cancelled.future,
            );
            onStatus?.call('正在等待系统引擎合成音频');
            final result = await _systemCall(
              system.synthesizeToFile(text, path, true),
              cancelled.future,
            );
            if (result != 1) throw StateError('系统 TTS 拒绝了合成请求');
            await finished;
          } finally {
            if (!completion.isCompleted) completion.complete();
            // Consume cancellation/errors even if dispatch itself failed first.
            await finished.catchError((Object _) {});
            system.setCompletionHandler(() {});
            system.setErrorHandler((_) {});
            system.setCancelHandler(() {});
          }
        case SpeechProvider.microsoftDemo:
          await file.writeAsBytes(
            await _microsoftDemo(
              text,
              settings,
              generation,
            ).timeout(const Duration(seconds: 60)),
          );
        case SpeechProvider.qwen:
          if (Uri.tryParse(settings.qwenEndpoint)?.scheme == 'wss') {
            await file.writeAsBytes(
              _paddedPcmWav(await _qwen(text, settings, generation)),
            );
            break;
          }
          final endpoint = Uri.tryParse(settings.qwenEndpoint);
          if (endpoint == null ||
              endpoint.scheme != 'https' ||
              !const {
                'dashscope.aliyuncs.com',
                'dashscope-intl.aliyuncs.com',
                'dashscope-us.aliyuncs.com',
              }.contains(endpoint.host)) {
            throw StateError('请选择官方 DashScope HTTPS 接口地址');
          }
          final response = await _http.post<Map<String, dynamic>>(
            endpoint.toString(),
            data: {
              'model': settings.qwenModel,
              'input': {
                'text': text,
                'voice': settings.qwenVoice,
                'language_type': 'Auto',
              },
            },
            options: Options(
              headers: {
                'Authorization': 'Bearer ${_credential(settings, 'qwenKey')}',
              },
            ),
            cancelToken: _cancel,
          );
          final audio = response.data?['output']?['audio'];
          final encoded = audio?['data'];
          if (encoded is String && encoded.isNotEmpty) {
            await file.writeAsBytes(base64Decode(encoded));
          } else {
            final url = Uri.tryParse(audio?['url'] as String? ?? '');
            if (url == null || url.scheme != 'https') {
              throw StateError('千问未返回有效的音频');
            }
            final bytes = await _http.get<List<int>>(
              url.toString(),
              options: Options(responseType: ResponseType.bytes),
              cancelToken: _cancel,
            );
            await file.writeAsBytes(bytes.data!);
          }
      }
      if (generation != _generation) throw StateError('已取消合成');
      if (!file.existsSync() || await file.length() == 0) {
        throw StateError('语音服务返回了空音频');
      }
      return file;
    } on TimeoutException {
      await cancel();
      throw StateError('语音引擎响应超时，请打开语音设置试听或更换引擎');
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      throw StateError(
        CancelToken.isCancel(error)
            ? '已取消合成'
            : '语音请求失败${status == null ? "，请检查网络" : "（HTTP $status），请检查凭据、地域和服务额度"}',
      );
    } finally {
      await _socket?.close().timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
      _socket = null;
    }
  }

  Future<T> _systemCall<T>(
    Future<T> operation,
    Future<void> cancelled, {
    int seconds = 10,
  }) => Future.any<T>([
    operation.timeout(Duration(seconds: seconds)),
    cancelled.then<T>((_) => throw StateError('已取消合成')),
  ]);

  Future<void> _configureSystem(
    ArticleSpeechSettings settings,
    Future<void> cancelled, {
    String? resolvedEngine,
    String? resolvedVoice,
  }) async {
    if (Platform.isAndroid) {
      final engine =
          resolvedEngine ??
          (settings.systemEngine.isEmpty
              ? await _systemCall(system.getDefaultEngine, cancelled) as String?
              : settings.systemEngine);
      if (engine != null && engine.isNotEmpty) {
        await _systemCall(useSystemEngine(engine), cancelled);
      }
    }
    final available = await _systemCall(
      system.isLanguageAvailable(settings.systemLocale),
      cancelled,
    );
    if (available != true && available != 1) {
      throw StateError('系统 TTS 缺少所选语言，请打开系统 TTS 设置安装语音数据');
    }
    await _systemCall(system.setLanguage(settings.systemLocale), cancelled);
    final voice = resolvedVoice ?? settings.systemVoice;
    if (voice.isNotEmpty) {
      await _systemCall(
        system.setVoice({
          'name': voice,
          'locale': settings.systemLocale,
        }),
        cancelled,
      );
    }
    await _systemCall(system.setSpeechRate(.5), cancelled);
  }

  Future<void> previewSystem(ArticleSpeechSettings settings) async {
    await cancel();
    _usingSystem = true;
    final signal = _cancelSignal = Completer<void>();
    await _configureSystem(settings, signal.future);
    await _systemCall(system.awaitSpeakCompletion(false), signal.future);
    final result = await _systemCall(
      system.speak('你好，这是系统文字转语音试听。欢迎使用专栏听书。', focus: true),
      signal.future,
    );
    if (result != 1) throw StateError('系统 TTS 试听失败，请检查默认引擎及音量');
  }

  String _credential(ArticleSpeechSettings settings, String key) {
    final value = settings.credentials[key]?.trim() ?? '';
    if (value.isEmpty) throw StateError('请先填写${settings.provider.label}的完整凭据');
    return value;
  }

  String _requestId() {
    final random = Random.secure();
    final hex = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<WebSocket> _openSocket(
    Uri uri,
    Map<String, String> headers,
    int generation,
  ) async {
    final connecting = _connectWebSocket(uri, headers);
    // Close a handshake that finishes after cancellation or timeout.
    unawaited(
      connecting.then((socket) async {
        if (generation != _generation) await socket.close();
      }, onError: (Object _) {}),
    );
    final socket = await _systemCall(
      connecting,
      _cancelSignal!.future,
      seconds: 15,
    );
    if (generation != _generation) {
      await socket.close();
      throw StateError('已取消合成');
    }
    _socket = socket;
    return socket;
  }

  // Protocol reference: jing332/tts-server-go, tts/azure/azure.go.
  Future<Uint8List> _microsoftDemo(
    String text,
    ArticleSpeechSettings settings,
    int generation,
  ) async {
    final id = _requestId().replaceAll('-', '');
    final uri = Uri.https(
      'eastus.api.speech.microsoft.com',
      '/cognitiveservices/websocket/v1',
      {
        'TricType': 'AzureDemo',
        'Authorization': 'bearer undefined',
        'X-ConnectionId': id,
      },
    ).replace(scheme: 'wss');
    final socket = await _openSocket(uri, {
      'Origin': 'https://azure.microsoft.com',
    }, generation);
    void send(String path, String type, String body) {
      socket.add(
        'Path: $path\r\nX-RequestId: $id\r\nX-Timestamp: ${DateTime.now().toUtc().toIso8601String()}\r\nContent-Type: $type\r\n\r\n$body',
      );
    }

    send(
      'speech.config',
      'application/json',
      jsonEncode({
        'context': {
          'system': {
            'name': 'PiliNara',
            'version': '1.0',
            'build': 'Dart',
            'lang': 'Dart',
          },
        },
      }),
    );
    send(
      'synthesis.context',
      'application/json',
      jsonEncode({
        'synthesis': {
          'audio': {
            'metadataOptions': {
              'sentenceBoundaryEnabled': false,
              'wordBoundaryEnabled': false,
            },
            'outputFormat': 'audio-24khz-48kbitrate-mono-mp3',
          },
        },
      }),
    );
    const escapeText = HtmlEscape(HtmlEscapeMode.element);
    const escapeAttribute = HtmlEscape(HtmlEscapeMode.attribute);
    final locale = escapeAttribute.convert(settings.microsoftLocale);
    final voice = escapeAttribute.convert(settings.microsoftVoice);
    send(
      'ssml',
      'application/ssml+xml',
      '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="$locale"><voice name="$voice"><break time="300ms"/>${escapeText.convert(text)}<break time="300ms"/></voice></speak>',
    );
    final audio = BytesBuilder(copy: false);
    final pathHeader = RegExp(
      r'^Path:\s*([^\r\n]+)',
      multiLine: true,
      caseSensitive: false,
    );
    await for (final frame in socket.timeout(const Duration(seconds: 45))) {
      if (generation != _generation) throw StateError('已取消合成');
      if (frame is List<int>) {
        if (frame.length < 2) throw StateError('微软演示返回了无效的音频帧');
        final headerLength = (frame[0] << 8) | frame[1];
        final offset = 2 + headerLength;
        if (offset > frame.length) throw StateError('微软演示返回了不完整的音频帧');
        final header = utf8.decode(frame.sublist(2, offset));
        if (pathHeader.firstMatch(header)?.group(1)?.trim().toLowerCase() ==
            'audio') {
          audio.add(frame.sublist(offset));
        }
      } else if (frame is String &&
          pathHeader.firstMatch(frame)?.group(1)?.trim().toLowerCase() ==
              'turn.end') {
        return audio.takeBytes();
      }
    }
    throw StateError('微软演示连接提前结束，请重试');
  }

  Future<Uint8List> _qwen(
    String text,
    ArticleSpeechSettings settings,
    int generation,
  ) async {
    final uri = Uri.parse(settings.qwenEndpoint);
    final officialHost =
        const {
          'cn-beijing.maas.qianwenaiapi.com',
          'dashscope.aliyuncs.com',
          'dashscope-intl.aliyuncs.com',
        }.contains(uri.host) ||
        RegExp(
          r'^[a-zA-Z0-9-]+\.(cn-beijing|ap-southeast-1)\.maas\.aliyuncs\.com$',
        ).hasMatch(uri.host);
    if (!officialHost ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 443) ||
        uri.path != '/api-ws/v1/inference') {
      throw StateError('请填写官方千问 WebSocket 合成接口地址');
    }
    final key = _credential(settings, 'qwenKey');
    final socket = await _openSocket(uri, {
      'Authorization': 'Bearer $key',
      'User-Agent': 'PiliNara-ArticleTTS',
    }, generation);
    final taskId = _requestId();
    void send(String action, Map<String, dynamic> payload) {
      socket.add(
        jsonEncode({
          'header': {
            'action': action,
            'task_id': taskId,
            'streaming': 'duplex',
          },
          'payload': payload,
        }),
      );
    }

    send('run-task', {
      'task_group': 'audio',
      'task': 'tts',
      'function': 'SpeechSynthesizer',
      'model': settings.qwenModel,
      'parameters': {
        'text_type': 'PlainText',
        'voice': settings.qwenVoice,
        'format': 'pcm',
        'sample_rate': 22050,
        'volume': 50,
        'rate': 1,
        'pitch': 1,
        'enable_ssml': false,
      },
      'input': <String, dynamic>{},
    });
    final audio = BytesBuilder(copy: false);
    var started = false;
    await for (final frame in socket.timeout(const Duration(seconds: 45))) {
      if (generation != _generation) throw StateError('已取消合成');
      if (frame is List<int>) {
        audio.add(frame);
        continue;
      }
      final response = jsonDecode(frame as String) as Map<String, dynamic>;
      final header = response['header'];
      if (header?['task_id'] != taskId) continue;
      switch (header?['event']) {
        case 'task-started':
          if (started) continue;
          started = true;
          // Respect the service's per-message limit while keeping a long
          // paragraph in the same synthesis task and audio stream.
          final runes = text.runes.toList();
          var start = 0;
          while (start < runes.length) {
            var end = start;
            var units = 0;
            while (end < runes.length) {
              final width = runes[end] > 0xffff ? 2 : 1;
              if (units + width > 19000) break;
              units += width;
              end++;
            }
            send('continue-task', {
              'input': {
                'text': String.fromCharCodes(runes.sublist(start, end)),
              },
            });
            start = end;
          }
          send('finish-task', {'input': <String, dynamic>{}});
        case 'task-finished':
          return audio.takeBytes();
        case 'task-failed':
          throw StateError(
            '千问合成失败（${header?['error_code'] ?? '未知错误'}），请检查模型、音色、凭据和额度',
          );
      }
    }
    throw StateError('千问连接提前结束，请重试');
  }

  // Padding is part of the PCM stream, so the output device has time to
  // start and drain without trimming speech on either side of a segment.
  Uint8List _paddedPcmWav(Uint8List pcm) {
    if (pcm.isEmpty || pcm.length.isOdd) {
      throw StateError('千问返回的音频为空或不完整，请重试');
    }
    const sampleRate = 22050;
    const paddingBytes = 13230; // 300 ms of mono 16-bit PCM per side.
    final dataLength = pcm.length + paddingBytes * 2;
    final header = ByteData(44);
    void ascii(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        header.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    header.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    header
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, sampleRate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    header.setUint32(40, dataLength, Endian.little);
    return (BytesBuilder(copy: false)
          ..add(header.buffer.asUint8List())
          ..add(Uint8List(paddingBytes))
          ..add(pcm)
          ..add(Uint8List(paddingBytes)))
        .takeBytes();
  }

  Future<void> dispose({bool skipCancel = false}) async {
    if (!skipCancel) await cancel();
    _http.close(force: true);
  }
}
