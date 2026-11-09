import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'core/error/crash_reporter.dart';
import 'core/error/debug_log.dart';
import 'core/helpers/platform_helper.dart';
import 'core/l10n/app_localizations.dart';
import 'core/providers/settings_provider.dart';
import 'core/theme/questopia_theme.dart';
import 'features/library/presentation/library_screen.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isDesktopPlatform) {
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1100, 750),
        minimumSize: Size(650, 500),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  CrashReporter.install();
  DebugLog.install();
  runApp(
    const ProviderScope(
      child: QuestopiaApp(),
    ),
  );
}

class QuestopiaApp extends ConsumerWidget {
  const QuestopiaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    final mode = switch (settings.themeMode) {
      ThemeModeOption.light => ThemeMode.light,
      ThemeModeOption.dark || ThemeModeOption.amoled => ThemeMode.dark,
      ThemeModeOption.system => ThemeMode.system,
    };
    final isAmoled = settings.themeMode == ThemeModeOption.amoled;
    final useDynamic = settings.themeColor == 'dynamic';

    Locale? appLocale;
    if (settings.language != 'system' && settings.language.isNotEmpty) {
      appLocale = Locale(settings.language);
    }

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
          debugShowCheckedModeBanner: false,
          locale: appLocale,
          theme: QuestopiaTheme.light(
            accent: settings.themeColor,
            dynamicScheme: useDynamic ? lightDynamic : null,
          ),
          darkTheme: QuestopiaTheme.dark(
            accent: settings.themeColor,
            amoled: isAmoled,
            dynamicScheme: useDynamic ? darkDynamic : null,
          ),
          themeMode: mode,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: settings.isOnboardingCompleted
              ? const LibraryScreen()
              : const OnboardingScreen(),
        );
      },
    );
  }
}
