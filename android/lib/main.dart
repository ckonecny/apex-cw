import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_colors.dart';
import 'theme/nav_strip.dart';
import 'theme/theme_controller.dart';
import 'l10n/strings.dart';
import 'licenses.dart';
import 'util/bluetooth_hint.dart';
import 'util/key_adapter_state.dart';
import 'util/break_reminder.dart';
import 'util/focus_mode.dart';
import 'util/interference_profile.dart';
import 'util/paddle_layout.dart';
import 'util/practice_clock.dart';
import 'util/reminder.dart';
import 'util/app_shortcuts.dart';
import 'util/share_intake.dart';
import 'ui/home_screen.dart';
import 'ui/widgets/app_ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  await ThemeController.load();
  await BlueLightFilter.load();
  await StatusBarMode.load();
  await CompactTop.load();
  await Strings.load();
  await PaddleLayout.load();
  registerAppLicenses();
  InterferenceProfile.pushSaved();
  await PracticeClock.instance.init();
  await FocusMode.init();
  PracticeClock.instance.onIdle = () {
    Reminder.refresh();
    FocusMode.release();
  };
  PracticeClock.instance.onActive = FocusMode.engage;
  Reminder.refresh();
  runApp(const NextCwTrainerApp());
  ShareIntake.init();
  AppShortcuts.init();
  BluetoothHint.init();
  KeyAdapterState.init();
  BreakReminder.init();
}

class NextCwTrainerApp extends StatelessWidget {
  const NextCwTrainerApp({super.key});

  ThemeData _theme(AppColors c, Brightness brightness, {bool variant = false}) => ThemeData(
        extensions: [if (variant) ThemeVariantMarker(c)],
        brightness: brightness,
        colorScheme: ColorScheme(
          brightness: brightness,
          primary: c.accent,
          onPrimary: brightness == Brightness.dark ? Colors.black : Colors.white,
          secondary: c.info,
          onSecondary: Colors.white,
          error: c.danger,
          onError: Colors.white,
          surface: c.surface,
          onSurface: c.textPrimary,
        ),
        fontFamily: 'DMSans',
        scaffoldBackgroundColor: c.background,
        useMaterial3: true,
      );

  ThemeData _darkTheme(int choice) {
    final v = ThemeController.variantOf(choice);
    return v == null
        ? _theme(AppColors.dark, Brightness.dark)
        : _theme(v, Brightness.dark, variant: true);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, _) => ValueListenableBuilder<int>(
        valueListenable: ThemeController.choice,
        builder: (context, choice, _) => MaterialApp(
          navigatorKey: ShareIntake.navigatorKey,
          title: 'APEX CW',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeController.modeOf(choice),
          theme: _theme(AppColors.light, Brightness.light),
          darkTheme: _darkTheme(choice),
          // System font size is honoured up to 1.3× (Pixel step 4 of 7);
          // beyond that the fixed-geometry training screens stop fitting
          // (DECISIONS.md "System font size: capped at 1.3").
          //
          // Android 15+ forces edge-to-edge, so with 3-button navigation the
          // nav bar sits on top of every screen's bottom row (start buttons,
          // keyboards). Keep all routes clear of the system bars at the
          // bottom and sides once, here, instead of per screen; the strip
          // behind the nav bar gets the page background.
          //
          // The blue light filter wraps everything (dialogs and sheets live
          // inside the Navigator, so they are covered); off = no extra layer.
          builder: (context, child) {
            final app = ValueListenableBuilder<Color?>(
              valueListenable: NavStrip.color,
              builder: (context, strip, child) => ColoredBox(
                color: strip ?? Theme.of(context).scaffoldBackgroundColor,
                child: child,
              ),
              child: SafeArea(
                top: false,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: kMaxTextScale,
                  child: CompactTopArea(child: child!),
                ),
              ),
            );
            return ValueListenableBuilder<bool>(
              valueListenable: BlueLightFilter.enabled,
              builder: (context, on, _) => !on ? app
                  : ValueListenableBuilder<int>(
                      valueListenable: BlueLightFilter.strength,
                      builder: (context, s, _) => ColorFiltered(
                          colorFilter: BlueLightFilter.filter(s), child: app),
                    ),
            );
          },
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
