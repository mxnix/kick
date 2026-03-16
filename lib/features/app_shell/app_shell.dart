import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/kick_localizations.dart';
import '../shared/kick_surfaces.dart';
import 'first_run_disclaimer_gate.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final location = GoRouterState.of(context).uri.toString();
    final destinations = [
      _ShellDestination(
        route: '/home',
        label: l10n.navHome,
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home_rounded),
      ),
      _ShellDestination(
        route: '/accounts',
        label: l10n.navAccounts,
        icon: const Icon(Icons.group_outlined),
        selectedIcon: const Icon(Icons.group_rounded),
      ),
      _ShellDestination(
        route: '/settings',
        label: l10n.navSettings,
        icon: const Icon(Icons.tune_outlined),
        selectedIcon: const Icon(Icons.tune_rounded),
      ),
      _ShellDestination(
        route: '/logs',
        label: l10n.navLogs,
        icon: const Icon(Icons.receipt_long_outlined),
        selectedIcon: const Icon(Icons.receipt_long_rounded),
      ),
    ];

    final index = destinations.indexWhere((destination) => location.startsWith(destination.route));
    final selectedIndex = index == -1 ? 0 : index;

    return FirstRunDisclaimerGate(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useRail = constraints.maxWidth >= 1080;

          return Scaffold(
            extendBody: false,
            body: KickBackdrop(
              padding: EdgeInsets.fromLTRB(useRail ? 20 : 24, 20, useRail ? 20 : 24, 24),
              child: useRail
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ShellRail(
                          destinations: destinations,
                          selectedIndex: selectedIndex,
                          onSelected: (value) => _navigate(context, destinations[value]),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: KickContentFrame(
                            maxWidth: 920,
                            child: _AnimatedShellContent(location: location, child: child),
                          ),
                        ),
                      ],
                    )
                  : KickContentFrame(
                      maxWidth: 920,
                      child: _AnimatedShellContent(location: location, child: child),
                    ),
            ),
            bottomNavigationBar: useRail
                ? null
                : SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _BottomNav(
                      destinations: destinations,
                      selectedIndex: selectedIndex,
                      onSelected: (value) => _navigate(context, destinations[value]),
                    ),
                  ),
          );
        },
      ),
    );
  }

  void _navigate(BuildContext context, _ShellDestination destination) {
    final currentLocation = GoRouterState.of(context).uri.toString();
    if (!currentLocation.startsWith(destination.route)) {
      context.go(destination.route);
    }
  }
}

class _AnimatedShellContent extends StatefulWidget {
  const _AnimatedShellContent({required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  State<_AnimatedShellContent> createState() => _AnimatedShellContentState();
}

class _AnimatedShellContentState extends State<_AnimatedShellContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 160),
    value: 1,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.012),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void didUpdateWidget(covariant _AnimatedShellContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_ShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const radius = 32.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: KickPanel(
        padding: EdgeInsets.zero,
        radius: radius,
        child: NavigationBar(
          selectedIndex: selectedIndex,
          destinations: destinations
              .map(
                (destination) => NavigationDestination(
                  icon: destination.icon,
                  selectedIcon: destination.selectedIcon,
                  label: destination.label,
                ),
              )
              .toList(growable: false),
          onDestinationSelected: onSelected,
        ),
      ),
    );
  }
}

class _ShellRail extends StatelessWidget {
  const _ShellRail({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_ShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: 220,
      child: KickPanel(
        tone: KickPanelTone.soft,
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
        radius: 32,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.appTitle, style: textTheme.headlineMedium),
                  const SizedBox(height: 6),
                  Text(
                    l10n.shellSubtitle,
                    style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: NavigationRail(
                extended: true,
                selectedIndex: selectedIndex,
                onDestinationSelected: onSelected,
                backgroundColor: Colors.transparent,
                leading: const SizedBox(height: 8),
                destinations: destinations
                    .map(
                      (destination) => NavigationRailDestination(
                        icon: destination.icon,
                        selectedIcon: destination.selectedIcon,
                        label: Text(destination.label),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellDestination {
  const _ShellDestination({
    required this.route,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String route;
  final String label;
  final Widget icon;
  final Widget selectedIcon;
}
