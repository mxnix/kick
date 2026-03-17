import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/user_facing_error_formatter.dart';
import '../core/platform/window_bootstrap.dart';
import '../core/platform/windows_desktop_runtime.dart';
import '../core/theme/kick_theme.dart';
import '../features/shared/kick_surfaces.dart';
import '../features/shared/kick_window_frame.dart';
import '../l10n/kick_localizations.dart';
import 'app.dart';
import 'bootstrap.dart';

class KickBootstrapGate extends StatefulWidget {
  const KickBootstrapGate({super.key});

  @override
  State<KickBootstrapGate> createState() => _KickBootstrapGateState();
}

class _KickBootstrapGateState extends State<KickBootstrapGate> {
  late final Future<AppBootstrap> _bootstrapFuture = initializeAppBootstrap();
  AppBootstrap? _resolvedBootstrap;
  KickThemeBootstrapData _themeBootstrapData = const KickThemeBootstrapData.unresolved();
  bool _bootstrapPresentationReleased = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadThemeBootstrapData());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (kDebugMode) {
        debugPrint('[bootstrap] loading shell first frame rendered');
      }
    });
  }

  Future<void> _loadThemeBootstrapData() async {
    final themeBootstrapData = await KickThemeBootstrapData.load();
    if (kDebugMode) {
      debugPrint(
        '[bootstrap] theme_bootstrap_ready dynamic=${themeBootstrapData.lightDynamicScheme != null}',
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _themeBootstrapData = themeBootstrapData;
    });
  }

  @override
  void dispose() {
    final bootstrap = _resolvedBootstrap;
    if (bootstrap != null) {
      unawaited(bootstrap.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppBootstrap>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          _releaseBootstrapPresentation();
        }

        final bootstrap = snapshot.data;
        if (bootstrap != null) {
          _resolvedBootstrap = bootstrap;
          return ProviderScope(
            key: const ValueKey('bootstrap-ready-scope'),
            overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
            child: KickApp(themeBootstrapData: _themeBootstrapData),
          );
        }

        return ProviderScope(
          key: const ValueKey('bootstrap-loading-scope'),
          child: _BootstrapShell(
            themeBootstrapData: _themeBootstrapData,
            child: snapshot.hasError
                ? _BootstrapErrorBody(error: snapshot.error!)
                : const _BootstrapLoadingBody(),
          ),
        );
      },
    );
  }

  void _releaseBootstrapPresentation() {
    if (_bootstrapPresentationReleased) {
      return;
    }

    _bootstrapPresentationReleased = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        WidgetsBinding.instance.allowFirstFrame();
      }
      if (!WindowsDesktopRuntime.startHiddenOnLaunch) {
        unawaited(WindowBootstrap.reveal());
      }
    });
  }
}

class _BootstrapShell extends StatelessWidget {
  const _BootstrapShell({required this.child, required this.themeBootstrapData});

  final Widget child;
  final KickThemeBootstrapData themeBootstrapData;

  @override
  Widget build(BuildContext context) {
    return KickThemeBuilder(
      themeMode: ThemeMode.system,
      useDynamicColor: true,
      bootstrapData: themeBootstrapData,
      builder: (lightTheme, darkTheme) {
        return MaterialApp(
          onGenerateTitle: (context) => context.l10n.appTitle,
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: ThemeMode.system,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => KickWindowFrame(
              statusLabelOverride: context.l10n.loadingValue,
              child: Scaffold(
                body: KickBackdrop(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: KickContentFrame(maxWidth: 560, alignment: Alignment.center, child: child),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BootstrapLoadingBody extends StatelessWidget {
  const _BootstrapLoadingBody();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return KickPanel(
      tone: KickPanelTone.soft,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.appTitle, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            l10n.loadingValue,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          const LinearProgressIndicator(minHeight: 6),
        ],
      ),
    );
  }
}

class _BootstrapErrorBody extends StatelessWidget {
  const _BootstrapErrorBody({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return EmptyStateCard(
      icon: Icons.error_outline_rounded,
      title: context.l10n.appTitle,
      message: formatUserFacingError(context.l10n, error),
    );
  }
}
