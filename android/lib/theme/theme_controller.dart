import 'dart:ui' show DisplayFeatureType;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_colors.dart';

/// App-wide theme, persisted and shared between Settings and main.dart.
/// 0=System (default), 1=Light, 2=Dark, then the dark-brightness variants
/// 3=Amber, 4=Red, 5=Green, 6=Warm grey, 7=Navy/Orange.
class ThemeController {
  static final ValueNotifier<int> choice = ValueNotifier(0);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    choice.value = (p.getInt('themeMode') ?? 0).clamp(0, 7);
  }

  static Future<void> set(int v) async {
    choice.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setInt('themeMode', v);
  }

  /// Palette for the dark-brightness variants (3-6), null for plain dark.
  static AppColors? variantOf(int v) => switch (v) {
        3 => AppColors.amber,
        4 => AppColors.red,
        5 => AppColors.green,
        6 => AppColors.warmGrey,
        7 => AppColors.navyOrange,
        _ => null,
      };

  static ThemeMode modeOf(int v) => switch (v) {
        1 => ThemeMode.light,
        >= 2 => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

/// Optional warm "blue light" filter over the whole app, for both themes.
/// Off by default; [strength] runs 10–100 (%).
class BlueLightFilter {
  static final ValueNotifier<bool> enabled = ValueNotifier(false);
  static final ValueNotifier<int> strength = ValueNotifier(50);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    enabled.value = p.getBool('blueLightOn') ?? false;
    strength.value = (p.getInt('blueLightStrength') ?? 50).clamp(10, 100);
  }

  static Future<void> setEnabled(bool v) async {
    enabled.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('blueLightOn', v);
  }

  static Future<void> setStrength(int v) async {
    strength.value = v.clamp(10, 100);
    final p = await SharedPreferences.getInstance();
    await p.setInt('blueLightStrength', strength.value);
  }

  /// Colour matrix that scales blue down hardest, green a little and red only
  /// by the overall dimming, so white turns a warm peach.
  static ColorFilter filter(int strength) {
    final t = strength / 100;
    // Also dims overall brightness (up to 20 %), so the brightest text
    // (stat values, quotas) stops glaring in the warm tone.
    final d = 1 - 0.20 * t;
    final g = (1 - 0.265 * t) * d;
    final b = (1 - 0.69 * t) * d;
    return ColorFilter.matrix(<double>[
      d, 0, 0, 0, 0,
      0, g, 0, 0, 0,
      0, 0, b, 0, 0,
      0, 0, 0, 1, 0,
    ]);
  }
}

/// Optionally hides the Android status bar (swipe down from the top edge shows
/// it briefly). Off by default. Re-applied on resume, as the system may bring
/// the bars back after another app was in front.
class StatusBarMode {
  static final ValueNotifier<bool> hidden = ValueNotifier(false);
  static AppLifecycleListener? _listener;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    hidden.value = p.getBool('hideStatusBar') ?? false;
    _listener ??= AppLifecycleListener(onResume: _apply);
    _apply();
  }

  static Future<void> set(bool v) async {
    hidden.value = v;
    _apply();
    final p = await SharedPreferences.getInstance();
    await p.setBool('hideStatusBar', v);
  }

  static void _apply() => hidden.value
      ? SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: [SystemUiOverlay.bottom])
      : SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}

/// Optional compact top area (only effective together with the hidden status
/// bar): the app bar moves up into the strip the status bar / camera cut-out
/// would otherwise occupy and gets slimmer. Off by default.
///
/// The switch alone is not enough: whether the layout really changes depends
/// on the phone ([CompactTop.evaluate]), and every screen reads the result
/// from its context ([CompactTop.of]).
class CompactTop {
  static final ValueNotifier<bool> enabled = ValueNotifier(false);

  /// True while the user wants it (switch on, status bar hidden).
  static bool get wanted => enabled.value && StatusBarMode.hidden.value;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    enabled.value = p.getBool('compactTop') ?? false;
  }

  static Future<void> set(bool v) async {
    enabled.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('compactTop', v);
  }

  /// Width of an app bar button in the compact layout (dp).
  static const double actionWidth = 34;

  /// Space kept free at the right edge (rounded display corner).
  static const double endPadding = 10;

  /// A button's inner padding: its box may reach this far into the cut-out's
  /// bounding box without the symbol touching the hole.
  static const double _glyphOverlap = 6;

  /// A cut-out wider than this share of the screen (notch) is not shared with
  /// the app bar; neither is one outside the central band (corner holes).
  static const double _maxCutoutShare = 0.2;
  static const double _bandStart = 0.25, _bandEnd = 0.75;

  /// What the compact layout can do on this phone. Not applied (normal
  /// layout, nothing hidden) when a cut-out at the top is wide, in a corner
  /// or leaves fewer than four buttons of room to its right.
  static CompactTopInfo evaluate(MediaQueryData mq, {required bool wanted}) {
    if (!wanted) return CompactTopInfo.off;
    final w = mq.size.width;
    final holes = [
      for (final f in mq.displayFeatures)
        if (f.type == DisplayFeatureType.cutout &&
            f.bounds.top <= 0)
          f.bounds,
    ];
    if (holes.isEmpty) {
      return const CompactTopInfo(applied: true, holeLeft: null, actionRoom: double.infinity);
    }
    var left = double.infinity, right = 0.0;
    for (final h in holes) {
      if (h.width > w * _maxCutoutShare ||
          h.left < w * _bandStart || h.right > w * _bandEnd) {
        return CompactTopInfo.off;
      }
      if (h.left < left) left = h.left;
      if (h.right > right) right = h.right;
    }
    final room = w - endPadding - (right - _glyphOverlap);
    if (room < 4 * actionWidth) return CompactTopInfo.off;
    return CompactTopInfo(applied: true, holeLeft: left, actionRoom: room);
  }

  static CompactTopInfo of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CompactTopScope>()?.info ??
      CompactTopInfo.off;
}

class CompactTopInfo {
  /// The compact layout is in use on this screen.
  final bool applied;

  /// Left edge of the top cut-out (null = none): titles must end before it.
  final double? holeLeft;

  /// Width right of the cut-out available for app bar buttons.
  final double actionRoom;
  const CompactTopInfo({required this.applied, required this.holeLeft, required this.actionRoom});
  static const off = CompactTopInfo(applied: false, holeLeft: null, actionRoom: double.infinity);

  /// Whether [n] buttons fit beside the cut-out (always true when not applied).
  bool fits(int n) => !applied || n * CompactTop.actionWidth <= actionRoom;
}

class _CompactTopScope extends InheritedWidget {
  final CompactTopInfo info;
  const _CompactTopScope({required this.info, required super.child});

  @override
  bool updateShouldNotify(_CompactTopScope old) =>
      old.info.applied != info.applied ||
      old.info.holeLeft != info.holeLeft ||
      old.info.actionRoom != info.actionRoom;
}

/// Wraps the routes: provides [CompactTop.of] and, when applied, drops the top
/// inset (the camera cut-out's height on most phones) so every app bar sits in
/// that strip, and slims the app bars.
class CompactTopArea extends StatelessWidget {
  final Widget child;
  const CompactTopArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([CompactTop.enabled, StatusBarMode.hidden]),
      builder: (context, _) {
        final mq = MediaQuery.of(context);
        final info = CompactTop.evaluate(mq, wanted: CompactTop.wanted);
        if (!info.applied) return _CompactTopScope(info: info, child: child);
        final theme = Theme.of(context);
        return _CompactTopScope(
          info: info,
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: Theme(
              data: theme.copyWith(
                appBarTheme: theme.appBarTheme.copyWith(
                  toolbarHeight: 44,
                  leadingWidth: 44,
                  titleSpacing: 8,
                  // Clear of the rounded display corner (the app bar now
                  // sits at the very top edge).
                  actionsPadding: const EdgeInsetsDirectional.only(
                      end: CompactTop.endPadding),
                  iconTheme: const IconThemeData(size: 20),
                  actionsIconTheme: const IconThemeData(size: 20),
                ),
                iconButtonTheme: IconButtonThemeData(
                  style: IconButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(CompactTop.actionWidth, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
