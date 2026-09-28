import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_colors.dart';
import 'theme/theme_controller.dart';
import 'l10n/strings.dart';
import 'licenses.dart';
import 'ui/home_screen.dart';
import 'ui/widgets/app_ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  await ThemeController.load();
  await Strings.load();
  registerAppLicenses();
  runApp(const NextCwTrainerApp());
}

class NextCwTrainerApp extends StatelessWidget {
  const NextCwTrainerApp({super.key});

  ThemeData _theme(AppColors c, Brightness brightness) => ThemeData(
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
        scaffoldBackgroundColor: c.background,
        useMaterial3: true,
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Strings.lang,
      builder: (context, _, __) => ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeController.mode,
        builder: (context, mode, _) => MaterialApp(
          title: 'Next CW Trainer',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: _theme(AppColors.light, Brightness.light),
          darkTheme: _theme(AppColors.dark, Brightness.dark),
          // System font size is honoured up to 1.3× (Pixel step 4 of 7);
          // beyond that the fixed-geometry training screens stop fitting
          // (DECISIONS.md "System font size: capped at 1.3").
          //
          // Android 15+ forces edge-to-edge, so with 3-button navigation the
          // nav bar sits on top of every screen's bottom row (start buttons,
          // keyboards). Keep all routes clear of the system bars at the
          // bottom and sides once, here, instead of per screen; the strip
          // behind the nav bar gets the page background.
          builder: (context, child) => ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: SafeArea(
              top: false,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: kMaxTextScale,
                child: child!,
              ),
            ),
          ),
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
