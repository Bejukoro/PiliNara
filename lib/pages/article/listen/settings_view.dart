import 'dart:io';

import 'package:flutter/services.dart';

import 'package:PiliPlus/pages/article/listen/synthesizer.dart';
import 'package:PiliPlus/pages/article/listen/settings.dart';
import 'package:PiliPlus/pages/article/listen/qwen_catalog.dart';
import 'package:PiliPlus/pages/article/listen/voice.dart';
import 'package:PiliPlus/pages/article/listen/microsoft_catalog.dart';
import 'package:material_ui/material_ui.dart';

class ArticleSpeechSettingsPage extends StatefulWidget {
  const ArticleSpeechSettingsPage({
    super.key,
    required this.settings,
    required this.synthesizer,
    required this.onSave,
  });
  final ArticleSpeechSettings settings;
  final ArticleSynthesizer synthesizer;
  final Future<void> Function(ArticleSpeechSettings) onSave;
  @override
  State<ArticleSpeechSettingsPage> createState() =>
      _ArticleSpeechSettingsPageState();
}

class _ArticleSpeechSettingsPageState extends State<ArticleSpeechSettingsPage> {
  late SpeechProvider provider = widget.settings.provider;
  final _fields = <String, TextEditingController>{};
  List<String> engines = [];
  List<Map<String, String>> voices = [];
  bool busy = false;
  bool catalogLoading = false;
  List<SpeechVoice> qwenVoices = [];
  String? catalogError;
  List<SpeechVoice> microsoftVoices = [];
  bool microsoftLoading = false;
  String? microsoftError;
  String? error;
  late String engine = widget.settings.systemEngine;
  late String voice = widget.settings.systemVoice;
  late String locale = widget.settings.systemLocale;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    error = s.credentialsError;
    final values = {
      ...s.credentials,
      'microsoftVoice': s.microsoftVoice,
      'microsoftLocale': s.microsoftLocale,
      'qwenVoice': s.qwenVoice,
      'qwenModel': s.qwenModel,
      'qwenEndpoint': s.qwenEndpoint,
    };
    for (final key in [
      'microsoftVoice',
      'microsoftLocale',
      'qwenKey',
      'qwenVoice',
      'qwenModel',
      'qwenEndpoint',
    ]) {
      _fields[key] = TextEditingController(text: values[key] ?? '');
    }
    if (provider == SpeechProvider.system) _loadVoices();
    if (provider == SpeechProvider.qwen) _loadQwenCatalog();
    if (provider == SpeechProvider.microsoftDemo) _loadMicrosoftCatalog();
  }

  Future<void> _loadQwenCatalog() async {
    if (catalogLoading) return;
    setState(() {
      catalogLoading = true;
      catalogError = null;
      if (qwenVoices.isEmpty) qwenVoices = QwenVoiceCatalog.cached();
    });
    try {
      final result = await QwenVoiceCatalog.fetch();
      if (mounted) setState(() => qwenVoices = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => catalogError = qwenVoices.isEmpty
              ? '音色目录获取失败，可重试或手动填写'
              : '目录更新失败，当前显示上次获取的音色',
        );
      }
    } finally {
      if (mounted) setState(() => catalogLoading = false);
    }
  }

  Future<void> _pickQwenModel() async {
    final models = qwenVoices.map((e) => e.model).toSet().toList();
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择千问模型'),
        children: [
          for (final model in models)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, model),
              child: Text(
                '$model（${qwenVoices.where((e) => e.model == model).length} 个音色）',
              ),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _fields['qwenModel']!.text = selected;
      final choices = qwenVoices.where((e) => e.model == selected);
      if (!choices.any((e) => e.id == _fields['qwenVoice']!.text.trim())) {
        _fields['qwenVoice']!.text = choices.first.id;
      }
      if (!_fields['qwenEndpoint']!.text.startsWith('wss://')) {
        _fields['qwenEndpoint']!.text = ArticleSpeechSettings().qwenEndpoint;
      }
    });
    await _pickQwenVoice();
  }

  Future<void> _pickQwenVoice() async {
    final model = _fields['qwenModel']!.text.trim();
    final candidates = qwenVoices.where((e) => e.model == model).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先从目录选择模型，或手动填写音色')));
      return;
    }
    final selected = await _chooseVoice(candidates, '选择千问音色');
    if (selected == null || !mounted) return;
    setState(() => _fields['qwenVoice']!.text = selected.id);
  }

  Future<SpeechVoice?> _chooseVoice(
    List<SpeechVoice> candidates,
    String title,
  ) {
    var query = '';
    var gender = '';
    return showDialog<SpeechVoice>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final filtered = candidates.where((voice) {
            final matchesGender = gender.isEmpty || voice.gender == gender;
            return matchesGender &&
                [
                  voice.name,
                  voice.id,
                  voice.gender,
                  voice.style,
                  voice.age,
                  voice.locale,
                ].join(' ').toLowerCase().contains(query.toLowerCase());
          }).toList();
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 600,
              height: MediaQuery.sizeOf(context).height * .55,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      labelText: '搜索名称、风格、性别、年龄',
                    ),
                    onChanged: (value) => update(() => query = value),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final value in ['', '女', '男'])
                        ChoiceChip(
                          label: Text(value.isEmpty ? '全部' : value),
                          selected: gender == value,
                          onSelected: (_) => update(() => gender = value),
                        ),
                    ],
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('没有匹配的音色'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final voice = filtered[index];
                              return ListTile(
                                title: Text(voice.name),
                                subtitle: Text(
                                  '${voice.id}\n性别 ${voice.gender.isEmpty ? "未标注" : voice.gender} · 年龄 ${voice.age.isEmpty ? "未标注" : voice.age}\n风格 ${voice.style.isEmpty ? "未标注" : voice.style}',
                                ),
                                onTap: () => Navigator.pop(context, voice),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _loadMicrosoftCatalog() async {
    if (microsoftLoading) return;
    setState(() {
      microsoftLoading = true;
      microsoftError = null;
      if (microsoftVoices.isEmpty) {
        microsoftVoices = MicrosoftDemoCatalog.cached();
      }
    });
    try {
      final voices = await MicrosoftDemoCatalog.fetch();
      if (mounted) setState(() => microsoftVoices = voices);
    } catch (_) {
      if (mounted) {
        setState(
          () => microsoftError = microsoftVoices.isEmpty
              ? '微软音色目录获取失败，可重试或手动填写'
              : '目录更新失败，当前显示上次获取的音色',
        );
      }
    } finally {
      if (mounted) setState(() => microsoftLoading = false);
    }
  }

  Future<void> _pickMicrosoftVoice() async {
    final selected = await _chooseVoice(microsoftVoices, '选择微软音色');
    if (selected == null || !mounted) return;
    setState(() {
      _fields['microsoftVoice']!.text = selected.id;
      _fields['microsoftLocale']!.text = selected.locale;
    });
  }

  Future<void> _loadVoices() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final tts = widget.synthesizer.system;
      if (Platform.isAndroid) {
        engines = List<String>.from(
          await tts.getEngines.timeout(const Duration(seconds: 10)) as List,
        );
        if (!engines.contains(engine)) engine = '';
        final selectedEngine = engine.isEmpty
            ? await tts.getDefaultEngine.timeout(const Duration(seconds: 10))
                  as String?
            : engine;
        if (selectedEngine != null && selectedEngine.isNotEmpty) {
          await widget.synthesizer
              .useSystemEngine(selectedEngine)
              .timeout(const Duration(seconds: 10));
        }
      }
      final result =
          await tts.getVoices.timeout(const Duration(seconds: 10)) as List;
      voices = result
          .map((e) => Map<String, String>.from(e as Map))
          .where((e) => e['name'] != null && e['locale'] != null)
          .toList();
    } catch (_) {
      error = '系统音色列表读取失败，可使用系统默认音色';
    }
    if (mounted) setState(() => busy = false);
  }

  String value(String key) => _fields[key]!.text.trim();
  Future<void> _preview() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.synthesizer.previewSystem(
        ArticleSpeechSettings()
          ..systemEngine = engine
          ..systemVoice = voice
          ..systemLocale = locale,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已向系统 TTS 发送试听请求')));
      }
    } catch (failure) {
      error = failure is StateError
          ? failure.message.toString()
          : '系统 TTS 试听失败，请检查已安装的引擎及语音数据';
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error!)));
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _openSystemSettings() async {
    try {
      await const MethodChannel('PiliNara')
          .invokeMethod<void>('openTtsSettings');
    } catch (_) {
      if (mounted) setState(() => error = '无法打开系统入口，请在手机设置中搜索“文字转语音”');
    }
  }

  Widget field(String key, String label, {bool secret = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: _fields[key],
      obscureText: secret,
      autocorrect: !secret,
      enableSuggestions: !secret,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Future<void> _save() async {
    setState(() {
      busy = true;
      error = null;
    });
    final requiredFields = switch (provider) {
      SpeechProvider.system => <String>[],
      SpeechProvider.microsoftDemo => ['microsoftVoice', 'microsoftLocale'],
      SpeechProvider.qwen => [
        'qwenKey',
        'qwenVoice',
        'qwenModel',
        'qwenEndpoint',
      ],
    };
    if (requiredFields.any((key) => value(key).isEmpty)) {
      setState(() {
        busy = false;
        error = '请填写完整的凭据和音色配置';
      });
      return;
    }
    final s = ArticleSpeechSettings()
      ..credentialsError = widget.settings.credentialsError
      ..provider = provider
      ..systemEngine = engine
      ..systemVoice = voice
      ..systemLocale = locale
      ..rate = widget.settings.rate
      ..microsoftVoice = value('microsoftVoice')
      ..microsoftLocale = value('microsoftLocale')
      ..qwenVoice = value('qwenVoice')
      ..qwenModel = value('qwenModel')
      ..qwenEndpoint = value('qwenEndpoint')
      ..credentials = {'qwenKey': value('qwenKey')};
    try {
      await widget.onSave(s);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '设置保存失败，请重试';
        });
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('听书语音设置'),
      actions: [
        TextButton(onPressed: busy ? null : _save, child: const Text('保存')),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.settings.credentialsError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              widget.settings.credentialsError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        DropdownButtonFormField<SpeechProvider>(
          initialValue: provider,
          decoration: const InputDecoration(labelText: '语音服务'),
          items: [
            for (final p in SpeechProvider.values)
              DropdownMenuItem(value: p, child: Text(p.label)),
          ],
          onChanged: busy
              ? null
              : (p) {
                  setState(() => provider = p!);
                  if (provider == SpeechProvider.system) _loadVoices();
                  if (provider == SpeechProvider.qwen) _loadQwenCatalog();
                  if (provider == SpeechProvider.microsoftDemo) {
                    _loadMicrosoftCatalog();
                  }
                },
        ),
        const SizedBox(height: 20),
        if (provider == SpeechProvider.system) ...[
          if (Platform.isAndroid)
            DropdownButtonFormField<String>(
              key: ValueKey('engine:$engine'),
              initialValue: engines.contains(engine) ? engine : '',
              decoration: const InputDecoration(labelText: '系统语音引擎'),
              items: [
                const DropdownMenuItem(value: '', child: Text('系统默认')),
                for (final name in engines)
                  DropdownMenuItem(
                    value: name,
                    child: Text(name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (v) {
                      setState(() {
                        engine = v!;
                        voice = '';
                      });
                      _loadVoices();
                    },
              isExpanded: true,
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('voice:$engine:${voices.length}'),
            initialValue: voices.any((e) => e['name'] == voice) ? voice : '',
            decoration: const InputDecoration(labelText: '音色'),
            items: [
              const DropdownMenuItem(value: '', child: Text('默认中文音色')),
              for (final item in {
                for (final item in voices) item['name']!: item,
              }.values)
                DropdownMenuItem(
                  value: item['name'],
                  child: Text(
                    '${item['name']}（${item['locale']}）',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            isExpanded: true,
            onChanged: busy
                ? null
                : (v) => setState(() {
                    voice = v!;
                    locale =
                        voices
                            .where((e) => e['name'] == v)
                            .firstOrNull?['locale'] ??
                        'zh-CN';
                  }),
          ),
          const SizedBox(height: 16),
          const Text('音色和离线能力由手机安装的 TTS 引擎提供。可在系统“文字转语音”设置中安装中文语音数据。'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : _preview,
            icon: const Icon(Icons.play_arrow),
            label: const Text('系统 TTS 试听'),
          ),
          if (Platform.isAndroid)
            TextButton.icon(
              onPressed: _openSystemSettings,
              icon: const Icon(Icons.settings),
              label: const Text('打开系统 TTS 设置'),
            ),
        ],
        if (provider == SpeechProvider.microsoftDemo) ...[
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: microsoftVoices.isEmpty ? null : _pickMicrosoftVoice,
                child: const Text('选择音色'),
              ),
              TextButton(
                onPressed: microsoftLoading ? null : _loadMicrosoftCatalog,
                child: Text(microsoftLoading ? '正在获取目录…' : '刷新微软目录'),
              ),
            ],
          ),
          if (microsoftError != null) Text(microsoftError!),
          field('microsoftVoice', '微软音色 ID（支持手动填写）'),
          field('microsoftLocale', '音色语言，例如 zh-CN'),
        ],
        if (provider == SpeechProvider.qwen) ...[
          field('qwenKey', 'DashScope API Key', secret: true),
          field('qwenEndpoint', '合成接口地址（wss:// 或 HTTPS）'),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: qwenVoices.isEmpty ? null : _pickQwenModel,
                child: const Text('选择模型'),
              ),
              OutlinedButton(
                onPressed: qwenVoices.isEmpty ? null : _pickQwenVoice,
                child: const Text('选择音色'),
              ),
              TextButton(
                onPressed: catalogLoading ? null : _loadQwenCatalog,
                child: Text(catalogLoading ? '正在获取目录…' : '刷新官方目录'),
              ),
            ],
          ),
          const Text('目录来自官方音色列表。未公开的风格、性别或年龄显示为“未标注”，可用范围以账号和地域为准。'),
          if (catalogError != null) Text(catalogError!),
          field('qwenModel', '模型 ID（支持手动填写）'),
          field('qwenVoice', '音色 ID（支持手动填写）'),
        ],
        if (provider == SpeechProvider.qwen)
          const Text(
            '使用你在服务商开通的免费额度。额度有效期和上限以服务商控制台为准，超额可能计费。请在控制台设置额度或付费限制。API 凭据保存在系统安全存储中。',
          ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}
