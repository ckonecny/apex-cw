import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_colors.dart';
import 'theme/theme_controller.dart';
import 'l10n/strings.dart';
import 'ui/home_screen.dart';
import 'ui/widgets/app_ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  await ThemeController.load();
  await Strings.load();
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
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            maxScaleFactor: kMaxTextScale,
            child: child!,
          ),
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
