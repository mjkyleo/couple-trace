import 'package:flutter/material.dart';

/// Trace · 同迹 设计令牌。
///
/// 取对比稿 S1「双轨」的色板，但先只落"两人各有固定色"这一条，
/// 双轨版式（中缝刻度、左右分栏）留到 UI 优化阶段再做，
/// 因为普通列表 + 头像着色已经能表达"谁说的"，不必先付自定义绘制的成本。
class TraceColors {
  TraceColors._();

  static const Color paper = Color(0xFFF7F8F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF1B1F1D);
  static const Color inkSoft = Color(0xFF6E7873);
  static const Color hairline = Color(0xFFDCE1DC);

  /// 两人固定配色：自己 = 琥珀，对方 = 靛蓝。
  /// 不随内容变化，用户在任意一条动态上都能凭颜色分辨作者。
  static const Color me = Color(0xFFC08A18);
  static const Color partner = Color(0xFF2F5D8C);

  /// 唯一强调色，只用于破坏性动作与未读提示，不参与装饰
  static const Color alert = Color(0xFF9E2B25);
}

/// 字号档位（个性化设置可切换）
enum TextScaleLevel { small, normal, large }

ThemeData buildTraceTheme({TextScaleLevel level = TextScaleLevel.normal}) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: TraceColors.partner,
      brightness: Brightness.light,
      surface: TraceColors.paper,
    ),
    scaffoldBackgroundColor: TraceColors.paper,
  );
  final scale = switch (level) {
    TextScaleLevel.small => 0.9,
    TextScaleLevel.normal => 1.0,
    TextScaleLevel.large => 1.15,
  };
  final text = base.textTheme.apply(fontSizeFactor: scale);
  return base.copyWith(
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: TraceColors.paper,
      foregroundColor: TraceColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: TraceColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: TraceColors.hairline),
        borderRadius: BorderRadius.circular(6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: TraceColors.ink,
        foregroundColor: TraceColors.paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: TraceColors.ink,
        side: const BorderSide(color: TraceColors.ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: TraceColors.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: TraceColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: TraceColors.partner),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),
  );
}

/// 根据当前用户 id 判断某条内容是自己发的还是对方发的
bool isMine(String publisherId, String? myId) => publisherId == myId;

/// 作者显示色：自己琥珀、对方靛蓝
Color authorColor(String publisherId, String? myId) =>
    isMine(publisherId, myId) ? TraceColors.me : TraceColors.partner;
