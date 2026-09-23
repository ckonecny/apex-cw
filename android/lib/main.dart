import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_colors.dart';
import 'theme/theme_controller.dart';
import 'l10n/strings.dart';
import 'ui/home_screen.dart';

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
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
