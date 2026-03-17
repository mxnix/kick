import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analytics/android_background_session_tracker.dart';
import '../core/platform/android_foreground_runtime.dart';
import '../core/theme/kick_theme.dart';
import '../features/app_state/providers.dart';
import '../features/shared/kick_window_frame.dart';
import '../l10n/kick_localizations.dart';
import 'bootstrap.dart';
import 'router.dart';

class KickApp extends ConsumerWidget {
  const KickApp({super.key, required this.themeBootstrapData});

  final KickThemeBootstrapData themeBootstrapData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final bootstrap = ref.watch(appBootstrapProvider);
    final settings =
        ref.watch(settingsControllerProvider).asData?.value ?? bootstrap.initialSettings;

    final app = KickThemeBuilder(
      themeMode: settings.themeMode,
      useDynamicColor: settings.useDynamicColor,
      bootstrapData: themeBootstrapData,
      builder: (lightTheme, darkTheme) {
        return MaterialApp.router(
          onGenerateTitle: (context) => context.l10n.appTitle,
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: settings.themeMode,
          themeAnimationCurve: Curves.easeOutCubic,
          themeAnimationDuration: const Duration(milliseconds: 420),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            return KickWindowFrame(child: child ?? const SizedBox.shrink());
          },
          routerConfig: router,
        );
      },
    );

    return ProxyConfigurationSync(
      child: AndroidBackgroundSessionScope(child: AndroidForegroundRuntimeScope(child: app)),
    );
  }
}
