import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/kick_theme.dart';
import '../../l10n/kick_localizations.dart';
import '../app_state/providers.dart';

class KickWindowFrame extends StatelessWidget {
  const KickWindowFrame({
    super.key,
    required this.child,
    this.statusLabelOverride,
    this.statusColorOverride,
  });

  final Widget child;
  final String? statusLabelOverride;
  final Color? statusColorOverride;

  @override
  Widget build(BuildContext context) {
    final usesKickDesktopFrame =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (!usesKickDesktopFrame) {
      return child;
    }

    return _DesktopWindowFrame(
      statusLabelOverride: statusLabelOverride,
      statusColorOverride: statusColorOverride,
      child: child,
    );
  }
}

class _DesktopWindowFrame extends ConsumerStatefulWidget {
  const _DesktopWindowFrame({
    required this.child,
    this.statusLabelOverride,
    this.statusColorOverride,
  });

  final Widget child;
  final String? statusLabelOverride;
  final Color? statusColorOverride;

  @override
  ConsumerState<_DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends ConsumerState<_DesktopWindowFrame> with WindowListener {
  bool _isFocused = true;
  bool _isMaximized = false;
  bool _isFullScreen = false;
  bool _isAlwaysOnTop = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_syncWindowState());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncWindowState() async {
    final isFocused = await windowManager.isFocused();
    final isMaximized = await windowManager.isMaximized();
    final isFullScreen = await windowManager.isFullScreen();
    final isAlwaysOnTop = await windowManager.isAlwaysOnTop();

    if (!mounted) {
      return;
    }

    setState(() {
      _isFocused = isFocused;
      _isMaximized = isMaximized;
      _isFullScreen = isFullScreen;
      _isAlwaysOnTop = isAlwaysOnTop;
    });
  }

  Future<void> _toggleAlwaysOnTop() async {
    final nextValue = !_isAlwaysOnTop;
    await windowManager.setAlwaysOnTop(nextValue);
    if (!mounted) {
      return;
    }

    setState(() {
      _isAlwaysOnTop = nextValue;
    });
  }

  @override
  void onWindowFocus() {
    setState(() => _isFocused = true);
  }

  @override
  void onWindowBlur() {
    setState(() => _isFocused = false);
  }

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
  }

  @override
  void onWindowRestore() {
    unawaited(_syncWindowState());
  }

  @override
  void onWindowEnterFullScreen() {
    setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    setState(() => _isFullScreen = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasOverrides = widget.statusLabelOverride != null || widget.statusColorOverride != null;
    final proxyStatus = hasOverrides
        ? null
        : (ref.watch(proxyStatusProvider).asData?.value ??
              ref.watch(proxyControllerProvider).currentState);
    final isProxyRunning = proxyStatus?.running ?? false;
    final radius = _isMaximized || _isFullScreen ? 0.0 : 20.0;
    final statusLabel =
        widget.statusLabelOverride ??
        (isProxyRunning ? context.l10n.proxyRunningStatus : context.l10n.proxyStoppedStatus);
    final statusColor =
        widget.statusColorOverride ??
        (isProxyRunning ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.72));

    return _DesktopVirtualFrame(
      isFocused: _isFocused,
      isMaximized: _isMaximized,
      isFullScreen: _isFullScreen,
      radius: radius,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ColoredBox(
          color: scheme.surface,
          child: Column(
            children: [
              _DesktopTitleBar(
                statusLabel: statusLabel,
                statusColor: statusColor,
                isFocused: _isFocused,
                isMaximized: _isMaximized,
                isAlwaysOnTop: _isAlwaysOnTop,
                onToggleAlwaysOnTop: _toggleAlwaysOnTop,
              ),
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopVirtualFrame extends StatelessWidget {
  const _DesktopVirtualFrame({
    required this.child,
    required this.isFocused,
    required this.isMaximized,
    required this.isFullScreen,
    required this.radius,
  });

  final Widget child;
  final bool isFocused;
  final bool isMaximized;
  final bool isFullScreen;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isWindowChromeExpanded = isMaximized || isFullScreen;
    final enableResizeEdges = isWindowChromeExpanded
        ? const <ResizeEdge>[]
        : defaultTargetPlatform == TargetPlatform.windows
        ? const <ResizeEdge>[ResizeEdge.topLeft, ResizeEdge.top, ResizeEdge.topRight]
        : null;

    return DragToResizeArea(
      enableResizeEdges: enableResizeEdges,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: isFocused ? 0.20 : 0.12),
            width: isWindowChromeExpanded ? 0 : 1,
          ),
        ),
        child: child,
      ),
    );
  }
}

class _DesktopTitleBar extends StatelessWidget {
  const _DesktopTitleBar({
    required this.statusLabel,
    required this.statusColor,
    required this.isFocused,
    required this.isMaximized,
    required this.isAlwaysOnTop,
    required this.onToggleAlwaysOnTop,
  });

  final String statusLabel;
  final Color statusColor;
  final bool isFocused;
  final bool isMaximized;
  final bool isAlwaysOnTop;
  final VoidCallback onToggleAlwaysOnTop;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scheme.surfaceContainerHigh.withValues(alpha: isFocused ? 0.78 : 0.52),
          scheme.surface,
        ),
        border: Border(
          bottom: BorderSide(color: scheme.onSurface.withValues(alpha: isFocused ? 0.10 : 0.06)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: context.kickTokens.shortDuration,
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      statusLabel,
                      style: textTheme.titleMedium?.copyWith(
                        color: isFocused
                            ? scheme.onSurfaceVariant
                            : scheme.onSurfaceVariant.withValues(alpha: 0.74),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _WindowHeaderButton(
            icon: Icons.push_pin_rounded,
            active: isAlwaysOnTop,
            tooltip: isAlwaysOnTop ? l10n.unpinWindowTooltip : l10n.pinWindowTooltip,
            onPressed: onToggleAlwaysOnTop,
          ),
          WindowCaptionButton.minimize(
            brightness: Theme.of(context).brightness,
            onPressed: () {
              unawaited(windowManager.minimize());
            },
          ),
          isMaximized
              ? WindowCaptionButton.unmaximize(
                  brightness: Theme.of(context).brightness,
                  onPressed: () {
                    unawaited(windowManager.unmaximize());
                  },
                )
              : WindowCaptionButton.maximize(
                  brightness: Theme.of(context).brightness,
                  onPressed: () {
                    unawaited(windowManager.maximize());
                  },
                ),
          WindowCaptionButton.close(
            brightness: Theme.of(context).brightness,
            onPressed: () {
              unawaited(windowManager.close());
            },
          ),
        ],
      ),
    );
  }
}

class _WindowHeaderButton extends StatefulWidget {
  const _WindowHeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;

  @override
  State<_WindowHeaderButton> createState() => _WindowHeaderButtonState();
}

class _WindowHeaderButtonState extends State<_WindowHeaderButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final backgroundColor = widget.active
        ? Color.alphaBlend(
            scheme.primary.withValues(alpha: _pressed ? 0.2 : 0.14),
            scheme.surfaceContainerHigh,
          )
        : _pressed
        ? scheme.surfaceContainerHigh.withValues(alpha: 0.96)
        : _hovered
        ? scheme.surfaceContainerHigh.withValues(alpha: 0.84)
        : Colors.transparent;

    final iconColor = widget.active
        ? scheme.primary
        : scheme.onSurfaceVariant.withValues(alpha: 0.9);

    return Semantics(
      label: widget.tooltip,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 32),
            decoration: BoxDecoration(color: backgroundColor),
            child: Center(child: Icon(widget.icon, size: 18, color: iconColor)),
          ),
        ),
      ),
    );
  }
}
