import 'dart:io';

import 'package:PiliPlus/utils/font_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:material_ui/material_ui.dart';

class ArticleReadingSettings {
  const ArticleReadingSettings({
    this.fontSize = 16,
    this.lineHeight = 1.6,
    this.paragraphSpacing = 10,
    this.pageMargin = 12,
    this.fontFamily,
  });

  final double fontSize;
  final double lineHeight;
  final double paragraphSpacing;
  final double pageMargin;
  final String? fontFamily;

  static ArticleReadingSettings load() {
    final value = GStorage.setting.get(SettingBoxKey.articleReadingSettings);
    final data = value is Map ? value : const {};
    double number(String key, double fallback, double min, double max) {
      final value = data[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    final family = data['fontFamily'];
    return ArticleReadingSettings(
      fontSize: number('fontSize', 16, 12, 32),
      lineHeight: number('lineHeight', 1.6, 1.0, 2.5),
      paragraphSpacing: number('paragraphSpacing', 10, 0, 32),
      pageMargin: number('pageMargin', 12, 0, 48),
      fontFamily:
          family is String &&
              FontUtils.customFonts.containsKey(family) &&
              File(FontUtils.customFonts[family]!).existsSync()
          ? family
          : null,
    );
  }

  TextStyle get textStyle =>
      TextStyle(fontSize: fontSize, height: lineHeight, fontFamily: fontFamily);

  Future<void> save() =>
      GStorage.setting.put(SettingBoxKey.articleReadingSettings, {
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'paragraphSpacing': paragraphSpacing,
        'pageMargin': pageMargin,
        'fontFamily': fontFamily,
      });
}

class ArticleReadingSettingsPanel extends StatefulWidget {
  const ArticleReadingSettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final ArticleReadingSettings settings;
  final ValueChanged<ArticleReadingSettings> onChanged;

  @override
  State<ArticleReadingSettingsPanel> createState() =>
      _ArticleReadingSettingsPanelState();
}

class _ArticleReadingSettingsPanelState
    extends State<ArticleReadingSettingsPanel> {
  late ArticleReadingSettings settings = widget.settings;
  bool importing = false;

  void update({double? size, double? height, double? spacing, double? margin}) {
    apply(
      ArticleReadingSettings(
        fontSize: size ?? settings.fontSize,
        lineHeight: height ?? settings.lineHeight,
        paragraphSpacing: spacing ?? settings.paragraphSpacing,
        pageMargin: margin ?? settings.pageMargin,
        fontFamily: settings.fontFamily,
      ),
    );
  }

  void apply(ArticleReadingSettings value) {
    setState(() => settings = value);
    widget.onChanged(value);
  }

  Future<void> selectFont(String family) async {
    apply(
      ArticleReadingSettings(
        fontSize: settings.fontSize,
        lineHeight: settings.lineHeight,
        paragraphSpacing: settings.paragraphSpacing,
        pageMargin: settings.pageMargin,
        fontFamily: family.isEmpty ? null : family,
      ),
    );
    if (family.isNotEmpty) await FontUtils.loadFontIfNecessary(family);
    if (mounted && settings.fontFamily == family) setState(() {});
  }

  Future<void> importFont() async {
    setState(() => importing = true);
    try {
      final family = await FontUtils.pickFonts();
      if (mounted && family != null) await selectFont(family);
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Widget slider(
    String label,
    double value,
    double min,
    double max,
    int divisions,
    ValueChanged<double> onChanged,
    String display,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label  $display'),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: display,
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Text('阅读设置')),
                TextButton(
                  onPressed: importing
                      ? null
                      : () => apply(const ArticleReadingSettings()),
                  child: const Text('恢复默认'),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            slider(
              '字号',
              settings.fontSize,
              12,
              32,
              20,
              (v) => update(size: v),
              settings.fontSize.toStringAsFixed(0),
            ),
            slider(
              '行间距',
              settings.lineHeight,
              1,
              2.5,
              30,
              (v) => update(height: v),
              '${settings.lineHeight.toStringAsFixed(2)} 倍',
            ),
            slider(
              '段间距',
              settings.paragraphSpacing,
              0,
              32,
              32,
              (v) => update(spacing: v),
              '${settings.paragraphSpacing.toStringAsFixed(0)} dp',
            ),
            slider(
              '左右页边距',
              settings.pageMargin,
              0,
              48,
              48,
              (v) => update(margin: v),
              '${settings.pageMargin.toStringAsFixed(0)} dp',
            ),
            DropdownButton<String>(
              isExpanded: true,
              value: FontUtils.isCustomFont(settings.fontFamily)
                  ? settings.fontFamily
                  : '',
              items: [
                const DropdownMenuItem(value: '', child: Text('跟随应用字体')),
                for (final family in FontUtils.customFonts.keys)
                  DropdownMenuItem(
                    value: family,
                    child: Text(
                      FontUtils.displayName(family),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: importing ? null : (value) => selectFont(value!),
            ),
            OutlinedButton.icon(
              onPressed: importing ? null : importFont,
              icon: const Icon(Icons.font_download_outlined),
              label: Text(importing ? '正在导入…' : '选择本地字体（TTF / OTF / TTC）'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: settings.pageMargin,
                vertical: 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '阅读预览 Aa 123，调整适合自己的字号和行间距。\n这是同一段落中的第二行。',
                    style: settings.textStyle,
                  ),
                  SizedBox(height: settings.paragraphSpacing),
                  Text('这是下一段。设置会自动保存。', style: settings.textStyle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
