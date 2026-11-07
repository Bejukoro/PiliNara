import 'dart:io';

import 'package:PiliPlus/pages/setting/slide_color_picker.dart';
import 'package:PiliPlus/utils/font_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:material_ui/material_ui.dart';

class ArticleReadingSettings {
  const ArticleReadingSettings({
    this.fontSize = 16,
    this.lineHeight = 1.6,
    this.paragraphSpacing = 10,
    this.pageMargin = 12,
    this.fontFamily,
    this.lightBackground,
    this.darkBackground,
  });

  final double fontSize;
  final double lineHeight;
  final double paragraphSpacing;
  final double pageMargin;
  final String? fontFamily;
  final Color? lightBackground;
  final Color? darkBackground;

  static const lightBackgrounds = <String, Color>{
    '暖纸': Color(0xFFF5EAD5),
    '米黄': Color(0xFFF2E2C2),
    '护眼绿': Color(0xFFCCE8CF),
    '浅灰': Color(0xFFE9E9E7),
    '纯白': Color(0xFFFFFFFF),
  };
  static const darkBackgrounds = <String, Color>{
    '夜间灰': Color(0xFF202124),
    '暖夜': Color(0xFF29241F),
    '墨绿': Color(0xFF18251F),
    'OLED 纯黑': Color(0xFF000000),
  };

  Color? backgroundFor(Brightness brightness) =>
      brightness == Brightness.light ? lightBackground : darkBackground;

  static Color readableOn(Color background, Color preferred) {
    final a = background.computeLuminance() + .05;
    final b = Color.alphaBlend(preferred, background).computeLuminance() + .05;
    if ((a > b ? a / b : b / a) >= 4.5) return preferred;
    return background.computeLuminance() > .179 ? Colors.black : Colors.white;
  }

  ThemeData readerTheme(ThemeData base) {
    final background = backgroundFor(base.brightness);
    if (background == null) return base;
    final brightness = background.computeLuminance() > .179
        ? Brightness.light
        : Brightness.dark;
    final foreground = readableOn(
      background,
      brightness == Brightness.light
          ? const Color(0xFF29251F)
          : const Color(0xFFE5E2DC),
    );
    final generated = ColorScheme.fromSeed(
      seedColor: base.colorScheme.primary,
      brightness: brightness,
    );
    final scheme = generated.copyWith(
      surface: background,
      surfaceDim: background,
      surfaceBright: background,
      surfaceContainerLowest: background,
      surfaceContainerLow: background,
      surfaceContainer: background,
      surfaceContainerHigh: background,
      surfaceContainerHighest: background,
      onSurface: foreground,
      onSurfaceVariant: foreground,
      onInverseSurface: background,
      outline: readableOn(background, generated.outline),
      primary: readableOn(background, generated.primary),
      onPrimary: background,
      secondary: readableOn(background, generated.secondary),
      onSecondary: background,
    );
    final overlay =
        (brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark)
            .copyWith(
              statusBarColor: background,
              systemNavigationBarColor: background,
              systemNavigationBarDividerColor: background,
              systemStatusBarContrastEnforced: false,
              systemNavigationBarContrastEnforced: false,
            );
    return base.copyWith(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: foreground.withValues(alpha: .15),
      textTheme: base.textTheme.apply(
        bodyColor: foreground,
        displayColor: foreground,
      ),
      iconTheme: base.iconTheme.copyWith(color: foreground),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: background,
        foregroundColor: foreground,
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
          color: foreground,
        ),
        toolbarTextStyle: base.appBarTheme.toolbarTextStyle?.copyWith(
          color: foreground,
        ),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: overlay,
        iconTheme: IconThemeData(color: foreground),
        actionsIconTheme: IconThemeData(color: foreground),
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: background,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          (base.popupMenuTheme.labelTextStyle?.resolve(const <WidgetState>{}) ??
                  const TextStyle())
              .copyWith(color: foreground),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.dialogTheme.titleTextStyle?.copyWith(
          color: foreground,
        ),
        contentTextStyle: base.dialogTheme.contentTextStyle?.copyWith(
          color: foreground,
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: background,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        backgroundColor: background,
        foregroundColor: foreground,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: background,
        modalBackgroundColor: background,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  static ArticleReadingSettings load() {
    final value = GStorage.setting.get(SettingBoxKey.articleReadingSettings);
    final data = value is Map ? value : const {};
    double number(String key, double fallback, double min, double max) {
      final value = data[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    Color? color(String key) {
      final value = data[key];
      return value is int && value >= 0 && value <= 0xFFFFFFFF
          ? Color(0xFF000000 | (value & 0xFFFFFF))
          : null;
    }

    final family = data['fontFamily'];
    return ArticleReadingSettings(
      lightBackground: color('lightBackground'),
      darkBackground: color('darkBackground'),
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
        'lightBackground': lightBackground?.toARGB32(),
        'darkBackground': darkBackground?.toARGB32(),
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
        lightBackground: settings.lightBackground,
        darkBackground: settings.darkBackground,
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
        lightBackground: settings.lightBackground,
        darkBackground: settings.darkBackground,
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

  void selectBackground(Brightness mode, Color? color) {
    apply(
      ArticleReadingSettings(
        fontSize: settings.fontSize,
        lineHeight: settings.lineHeight,
        paragraphSpacing: settings.paragraphSpacing,
        pageMargin: settings.pageMargin,
        fontFamily: settings.fontFamily,
        lightBackground: mode == Brightness.light
            ? color
            : settings.lightBackground,
        darkBackground: mode == Brightness.dark
            ? color
            : settings.darkBackground,
      ),
    );
  }

  Widget backgroundSection(Brightness mode) {
    final isLight = mode == Brightness.light;
    final selected = settings.backgroundFor(mode);
    final presets = isLight
        ? ArticleReadingSettings.lightBackgrounds
        : ArticleReadingSettings.darkBackgrounds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(isLight ? '亮色模式背景' : '暗色模式背景'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              label: const Text('跟随应用'),
              selected: selected == null,
              onSelected: (_) => selectBackground(mode, null),
            ),
            for (final preset in presets.entries)
              ChoiceChip(
                avatar: CircleAvatar(
                  backgroundColor: preset.value,
                  child: Icon(
                    Icons.circle_outlined,
                    size: 20,
                    color: ArticleReadingSettings.readableOn(
                      preset.value,
                      Colors.grey,
                    ),
                  ),
                ),
                label: Text(preset.key),
                selected: selected == preset.value,
                onSelected: (_) => selectBackground(mode, preset.value),
              ),
            ActionChip(
              label: Text(
                selected != null && !presets.containsValue(selected)
                    ? '#${selected.toARGB32().toRadixString(16).substring(2).toUpperCase()}'
                    : '自定义',
              ),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => Theme(
                  data: settings.readerTheme(Theme.of(context)),
                  child: AlertDialog(
                    title: Text(isLight ? '亮色模式背景色' : '暗色模式背景色'),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    content: SlideColorPicker(
                      color: selected ?? presets.values.first,
                      onChanged: (color) {
                        if (mounted && color != null) {
                          selectBackground(mode, color);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
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
    final readerTheme = settings.readerTheme(Theme.of(context));
    return Theme(
      data: readerTheme,
      child: Material(
        color: readerTheme.colorScheme.surface,
        child: SafeArea(
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
                backgroundSection(Brightness.light),
                backgroundSection(Brightness.dark),
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
                Container(
                  color: settings
                      .readerTheme(Theme.of(context))
                      .colorScheme
                      .surface,
                  padding: EdgeInsets.symmetric(
                    horizontal: settings.pageMargin,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '阅读预览 Aa 123，调整适合自己的字号和行间距。\n这是同一段落中的第二行。',
                        style: settings.textStyle.copyWith(
                          color: settings
                              .readerTheme(Theme.of(context))
                              .colorScheme
                              .onSurface,
                        ),
                      ),
                      SizedBox(height: settings.paragraphSpacing),
                      Text(
                        '这是下一段。设置会自动保存。',
                        style: settings.textStyle.copyWith(
                          color: settings
                              .readerTheme(Theme.of(context))
                              .colorScheme
                              .onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
