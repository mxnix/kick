import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:m3e_collection/m3e_collection.dart' as m3e;

import '../../app/app_metadata.dart';
import '../../core/theme/kick_icons.dart';
import '../../core/theme/kick_theme.dart';
import '../../l10n/kick_localizations.dart';
import '../shared/kick_haptics.dart';
import '../shared/kick_surfaces.dart';
import 'first_run_disclaimer_gate.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static double floatingNavigationClearanceOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_AppShellLayoutScope>()
            ?.floatingNavigationClearance ??
        0;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final location = GoRouterState.of(context).uri.toString();
    final destinations = [
      _ShellDestination(
        route: '/home',
        label: l10n.navHome,
        icon: const Icon(KickIcons.home),
        selectedIcon: const Icon(KickIcons.home),
      ),
      _ShellDestination(
        route: '/accounts',
        label: l10n.navAccounts,
        icon: const Icon(KickIcons.accounts),
        selectedIcon: const Icon(KickIcons.accounts),
      ),
      _ShellDestination(
        route: '/settings',
        label: l10n.navSettings,
        icon: const Icon(KickIcons.settings),
        selectedIcon: const Icon(KickIcons.settings),
      ),
      _ShellDestination(
        route: '/logs',
        label: l10n.navLogs,
        icon: const Icon(KickIcons.logs),
        selectedIcon: const Icon(KickIcons.logs),
      ),
    ];

    final index = destinations.indexWhere((destination) => location.startsWith(destination.route));
    final selectedIndex = index == -1 ? 0 : index;

    return FirstRunDisclaimerGate(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useRail = constraints.maxWidth >= 1080;
          final platform = Theme.of(context).platform;
          final useSystemInsets =
              platform == TargetPlatform.android ||
              platform == TargetPlatform.iOS ||
              platform == TargetPlatform.fuchsia;
          final floatingNavigationClearance = useRail
              ? 0.0
              : _floatingNavigationToolbarHeight +
                    math.max(
                      MediaQuery.paddingOf(context).bottom,
                      _floatingNavigationBottomMargin,
                    ) +
                    _floatingNavigationScrollGap;

          return _AppShellLayoutScope(
            floatingNavigationClearance: floatingNavigationClearance,
            child: Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(
                    child: KickBackdrop(
                      topInset: useSystemInsets,
                      bottomInset: useRail && useSystemInsets,
                      padding: EdgeInsets.fromLTRB(
                        useRail ? 20 : 24,
                        useRail ? 14 : 20,
                        useRail ? 20 : 24,
                        useRail ? 16 : 12,
                      ),
                      child: useRail
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ShellRail(
                                  destinations: destinations,
                                  selectedIndex: selectedIndex,
                                  onSelected: (value) => _navigate(context, destinations[value]),
                                  isExperimental: kickIsExperimentalBuild,
                                ),
                                const SizedBox(width: 24),
                                Expanded(
                                  child: KickContentFrame(
                                    maxWidth: 1360,
                                    expandHeight: true,
                                    child: _AnimatedShellContent(
                                      location: location,
                                      selectedIndex: selectedIndex,
                                      child: child,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : KickContentFrame(
                              maxWidth: 980,
                              expandHeight: true,
                              child: _AnimatedShellContent(
                                location: location,
                                selectedIndex: selectedIndex,
                                child: child,
                              ),
                            ),
                    ),
                  ),
                  if (!useRail)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _FloatingBottomNav(
                        destinations: destinations,
                        selectedIndex: selectedIndex,
                        onSelected: (value) => _navigate(context, destinations[value]),
                      ),
                    ),
                ],
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

const double _floatingNavigationBottomMargin = 20;
const double _floatingNavigationHorizontalMargin = 18;
const double _floatingNavigationItemSize = 56;
const double _floatingNavigationToolbarVerticalPadding = 8;
const double _floatingNavigationToolbarHeight =
    _floatingNavigationItemSize + _floatingNavigationToolbarVerticalPadding * 2;
const double _floatingNavigationScrollGap = 16;

class _AppShellLayoutScope extends InheritedWidget {
  const _AppShellLayoutScope({required this.floatingNavigationClearance, required super.child});

  final double floatingNavigationClearance;

  @override
  bool updateShouldNotify(_AppShellLayoutScope oldWidget) {
    return floatingNavigationClearance != oldWidget.floatingNavigationClearance;
  }
}

class _AnimatedShellContent extends StatefulWidget {
  const _AnimatedShellContent({
    required this.location,
    required this.selectedIndex,
    required this.child,
  });

  final String location;
  final int selectedIndex;
  final Widget child;

  @override
  State<_AnimatedShellContent> createState() => _AnimatedShellContentState();
}

class _AnimatedShellContentState extends State<_AnimatedShellContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );
  int _direction = 1;

  @override
  void didUpdateWidget(covariant _AnimatedShellContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      final indexDelta = widget.selectedIndex - oldWidget.selectedIndex;
      _direction = indexDelta == 0 ? 1 : indexDelta.sign;
      _controller.stop();
      unawaited(_controller.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.kickTokens;
    final curve = CurvedAnimation(parent: _controller, curve: tokens.emphasizedCurve);
    final direction = _direction == 0 ? 1 : _direction;
    final slide = Tween<Offset>(
      begin: Offset(direction * 0.06, 0),
      end: Offset.zero,
    ).animate(curve);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(position: slide, child: widget.child),
    );
  }
}

class _FloatingBottomNav extends StatelessWidget {
  const _FloatingBottomNav({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_ShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        _floatingNavigationHorizontalMargin,
        0,
        _floatingNavigationHorizontalMargin,
        _floatingNavigationBottomMargin,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SizedBox(
            width: double.infinity,
            child: _FloatingNavToolbar(
              destinations: destinations,
              selectedIndex: selectedIndex,
              onSelected: onSelected,
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingNavToolbar extends StatelessWidget {
  const _FloatingNavToolbar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_ShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const radius = 36.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(
              alpha: scheme.brightness == Brightness.dark ? 0.32 : 0.14,
            ),
            blurRadius: 28,
            spreadRadius: -8,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Material(
        clipBehavior: Clip.antiAlias,
        color: Color.alphaBlend(
          scheme.surface.withValues(alpha: 0.10),
          scheme.surfaceContainerHighest.withValues(alpha: 0.94),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.22)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            mainAxisSize: MainAxisSize.max,
            children: [
              for (final entry in destinations.indexed)
                _FloatingNavItem(
                  destination: entry.$2,
                  selected: entry.$1 == selectedIndex,
                  onPressed: () => onSelected(entry.$1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingNavItem extends StatelessWidget {
  const _FloatingNavItem({
    required this.destination,
    required this.selected,
    required this.onPressed,
  });

  final _ShellDestination destination;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.kickTokens;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: ExcludeSemantics(
        child: IconButton(
          tooltip: destination.label,
          onPressed: () {
            KickHaptics.selection();
            onPressed();
          },
          style: ButtonStyle(
            fixedSize: const WidgetStatePropertyAll(Size.square(_floatingNavigationItemSize)),
            minimumSize: const WidgetStatePropertyAll(Size.square(_floatingNavigationItemSize)),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            iconSize: const WidgetStatePropertyAll(26),
            shape: const WidgetStatePropertyAll(CircleBorder()),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (selected &&
                  (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused))) {
                return scheme.primary.withValues(alpha: 0.10);
              }
              if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
                return scheme.onSurfaceVariant.withValues(alpha: 0.08);
              }
              return Colors.transparent;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (selected) {
                return scheme.primary;
              }
              if (states.contains(WidgetState.pressed)) {
                return scheme.onSurface;
              }
              return scheme.onSurfaceVariant;
            }),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return scheme.primary.withValues(alpha: 0.12);
              }
              if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
                return scheme.primary.withValues(alpha: 0.08);
              }
              return Colors.transparent;
            }),
          ),
          icon: AnimatedScale(
            duration: tokens.shortDuration,
            curve: tokens.standardCurve,
            scale: selected ? 1.08 : 1,
            child: selected ? destination.selectedIcon : destination.icon,
          ),
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
    this.isExperimental = false,
  });

  final List<_ShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool isExperimental;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: 220,
      child: KickPanel(
        tone: KickPanelTone.soft,
        padding: EdgeInsets.zero,
        radius: 32,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(l10n.appTitle, style: textTheme.headlineMedium),
                      if (isExperimental) ...[const SizedBox(width: 8), _ShellExperimentalBadge()],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.shellSubtitle,
                    style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Expanded(
              child: m3e.NavigationRailM3E(
                type: m3e.NavigationRailM3EType.alwaysExpand,
                modality: m3e.NavigationRailM3EModality.standard,
                expandedWidth: 220,
                selectedIndex: selectedIndex,
                onDestinationSelected: onSelected,
                background: Colors.transparent,
                scrollable: false,
                sections: [
                  m3e.NavigationRailM3ESection(
                    destinations: destinations
                        .map(
                          (destination) => m3e.NavigationRailM3EDestination(
                            icon: destination.icon,
                            selectedIcon: destination.selectedIcon,
                            label: destination.label,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
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

class _ShellExperimentalBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.32)),
      ),
      child: Icon(KickIcons.science, size: 14, color: scheme.tertiary),
    );
  }
}
