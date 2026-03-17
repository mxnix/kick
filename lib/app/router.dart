import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/accounts/account_usage_page.dart';
import '../features/accounts/accounts_page.dart';
import '../features/app_shell/app_shell.dart';
import '../features/home/home_page.dart';
import '../features/logs/logs_page.dart';
import '../features/settings/about_page.dart';
import '../features/settings/settings_page.dart';
import '../observability/glitchtip.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    observers: glitchTipNavigatorObservers(),
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            name: 'home',
            pageBuilder: (context, state) => const NoTransitionPage(child: HomePage()),
          ),
          GoRoute(
            path: '/accounts',
            name: 'accounts',
            pageBuilder: (context, state) => const NoTransitionPage(child: AccountsPage()),
            routes: [
              GoRoute(
                path: ':accountId/usage',
                name: 'account-usage',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: AccountUsagePage(accountId: state.pathParameters['accountId']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            pageBuilder: (context, state) => NoTransitionPage(
              child: SettingsPage(initialSection: state.uri.queryParameters['section']),
            ),
            routes: [
              GoRoute(
                path: 'about',
                name: 'about',
                pageBuilder: (context, state) => const NoTransitionPage(child: AboutPage()),
              ),
            ],
          ),
          GoRoute(
            path: '/logs',
            name: 'logs',
            pageBuilder: (context, state) => const NoTransitionPage(child: LogsPage()),
          ),
        ],
      ),
    ],
  );
});
