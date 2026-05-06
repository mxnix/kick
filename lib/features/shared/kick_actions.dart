import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart' as m3e;

class KickPrimaryAction extends StatelessWidget {
  const KickPrimaryAction({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.fullWidth = false,
    this.busy = false,
    this.size = m3e.ButtonM3ESize.md,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool fullWidth;
  final bool busy;
  final m3e.ButtonM3ESize size;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasIcon = busy || icon != null;
        final labelMaxWidth = _buttonLabelMaxWidth(constraints, size: size, hasIcon: hasIcon);
        final button = m3e.ButtonM3E(
          onPressed: onPressed,
          enabled: !busy && onPressed != null,
          style: m3e.ButtonM3EStyle.filled,
          size: size,
          shape: m3e.ButtonM3EShape.square,
          icon: busy
              ? const KickLoadingIndicator(size: 22, contained: false)
              : icon == null
              ? null
              : Icon(icon),
          label: _ActionButtonLabel(label: label, maxWidth: labelMaxWidth),
        );

        if (!fullWidth) {
          return button;
        }
        return SizedBox(width: double.infinity, child: button);
      },
    );
  }
}

enum KickSecondaryActionVariant { outlined, tonal, text }

class KickSecondaryAction extends StatelessWidget {
  const KickSecondaryAction({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.fullWidth = false,
    this.busy = false,
    this.variant = KickSecondaryActionVariant.outlined,
    this.size = m3e.ButtonM3ESize.sm,
    this.dangerous = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool fullWidth;
  final bool busy;
  final KickSecondaryActionVariant variant;
  final m3e.ButtonM3ESize size;
  final bool dangerous;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = switch (variant) {
      KickSecondaryActionVariant.outlined => m3e.ButtonM3EStyle.outlined,
      KickSecondaryActionVariant.tonal => m3e.ButtonM3EStyle.tonal,
      KickSecondaryActionVariant.text => m3e.ButtonM3EStyle.text,
    };
    final foregroundColor = dangerous ? scheme.error : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasIcon = busy || icon != null;
        final labelMaxWidth = _buttonLabelMaxWidth(constraints, size: size, hasIcon: hasIcon);
        final button = m3e.ButtonM3E(
          onPressed: onPressed,
          enabled: !busy && onPressed != null,
          style: style,
          size: size,
          shape: m3e.ButtonM3EShape.square,
          icon: busy
              ? KickLoadingIndicator(size: 20, color: foregroundColor, contained: false)
              : icon == null
              ? null
              : Icon(icon, color: foregroundColor),
          label: _ActionButtonLabel(
            label: label,
            maxWidth: labelMaxWidth,
            style: foregroundColor == null ? null : TextStyle(color: foregroundColor),
          ),
        );

        if (!fullWidth) {
          return button;
        }
        return SizedBox(width: double.infinity, child: button);
      },
    );
  }
}

class _ActionButtonLabel extends StatelessWidget {
  const _ActionButtonLabel({required this.label, this.maxWidth, this.style});

  final String label;
  final double? maxWidth;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: style,
    );

    final resolvedMaxWidth = maxWidth;
    if (resolvedMaxWidth == null) {
      return text;
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: resolvedMaxWidth),
      child: text,
    );
  }
}

double? _buttonLabelMaxWidth(
  BoxConstraints constraints, {
  required m3e.ButtonM3ESize size,
  required bool hasIcon,
}) {
  if (!constraints.hasBoundedWidth) {
    return null;
  }

  final measurements = _actionButtonMeasurements(size);
  final reservedWidth =
      measurements.horizontalPadding * 2 +
      (hasIcon ? measurements.iconSize + measurements.iconGap : 0);
  return math.max(0, constraints.maxWidth - reservedWidth);
}

_ActionButtonMeasurements _actionButtonMeasurements(m3e.ButtonM3ESize size) {
  return switch (size) {
    m3e.ButtonM3ESize.xs => const _ActionButtonMeasurements(
      horizontalPadding: 12,
      iconSize: 20,
      iconGap: 4,
    ),
    m3e.ButtonM3ESize.sm => const _ActionButtonMeasurements(
      horizontalPadding: 16,
      iconSize: 20,
      iconGap: 8,
    ),
    m3e.ButtonM3ESize.md => const _ActionButtonMeasurements(
      horizontalPadding: 24,
      iconSize: 24,
      iconGap: 8,
    ),
    m3e.ButtonM3ESize.lg => const _ActionButtonMeasurements(
      horizontalPadding: 48,
      iconSize: 32,
      iconGap: 12,
    ),
    m3e.ButtonM3ESize.xl => const _ActionButtonMeasurements(
      horizontalPadding: 64,
      iconSize: 40,
      iconGap: 16,
    ),
  };
}

class _ActionButtonMeasurements {
  const _ActionButtonMeasurements({
    required this.horizontalPadding,
    required this.iconSize,
    required this.iconGap,
  });

  final double horizontalPadding;
  final double iconSize;
  final double iconGap;
}

class KickIconAction extends StatelessWidget {
  const KickIconAction({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.variant = m3e.IconButtonM3EVariant.standard,
    this.size = m3e.IconButtonM3ESize.sm,
    this.width = m3e.IconButtonM3EWidth.defaultWidth,
    this.shape = m3e.IconButtonM3EShapeVariant.square,
    this.selected,
    this.selectedIcon,
    this.badgeValue,
    this.dangerous = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final m3e.IconButtonM3EVariant variant;
  final m3e.IconButtonM3ESize size;
  final m3e.IconButtonM3EWidth width;
  final m3e.IconButtonM3EShapeVariant shape;
  final bool? selected;
  final IconData? selectedIcon;
  final Object? badgeValue;
  final bool dangerous;

  @override
  Widget build(BuildContext context) {
    final color = dangerous ? Theme.of(context).colorScheme.error : null;
    return m3e.IconButtonM3E(
      onPressed: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      icon: Icon(icon, color: color),
      selectedIcon: selectedIcon == null ? null : Icon(selectedIcon, color: color),
      isSelected: selected,
      variant: variant,
      size: size,
      width: width,
      shape: shape,
      badgeValue: badgeValue,
    );
  }
}

class KickLoadingIndicator extends StatelessWidget {
  const KickLoadingIndicator({
    super.key,
    this.size = 48,
    this.contained = true,
    this.color,
    this.semanticLabel,
  });

  final double size;
  final bool contained;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    const nativeSize = 48.0;

    return SizedBox.square(
      dimension: size,
      child: FittedBox(
        fit: BoxFit.contain,
        child: m3e.LoadingIndicatorM3E(
          variant: contained
              ? m3e.LoadingIndicatorM3EVariant.contained
              : m3e.LoadingIndicatorM3EVariant.defaultStyle,
          color: color,
          semanticLabel: semanticLabel,
          constraints: const BoxConstraints.tightFor(width: nativeSize, height: nativeSize),
        ),
      ),
    );
  }
}

class KickRefresh extends StatelessWidget {
  const KickRefresh({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return m3e.ExpressiveRefreshIndicator.contained(
      color: scheme.primary,
      backgroundColor: scheme.surfaceContainerHigh,
      onRefresh: onRefresh,
      child: child,
    );
  }
}
