import 'package:flutter/material.dart';

import '../../core/theme/kick_theme.dart';

class KickBackdrop extends StatelessWidget {
  const KickBackdrop({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(24, 24, 24, 104),
    this.topInset = true,
    this.bottomInset = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool topInset;
  final bool bottomInset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: scheme.surface,
      child: SafeArea(
        top: topInset,
        bottom: bottomInset,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class KickContentFrame extends StatelessWidget {
  const KickContentFrame({
    super.key,
    required this.child,
    this.maxWidth = 920,
    this.alignment = Alignment.topCenter,
    this.expandHeight = false,
  });

  final Widget child;
  final double maxWidth;
  final Alignment alignment;
  final bool expandHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = expandHeight && constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 0.0;

        return Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth, minHeight: minHeight),
            child: child,
          ),
        );
      },
    );
  }
}

enum KickPanelTone { soft, accent, outline, muted }

class KickPanel extends StatelessWidget {
  const KickPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.tone = KickPanelTone.soft,
    this.radius,
  });

  final Widget child;
  final EdgeInsets padding;
  final KickPanelTone tone;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedRadius = radius ?? context.kickTokens.panelRadius;
    final neutralSurface = Color.alphaBlend(
      scheme.surface.withValues(alpha: 0.08),
      scheme.surfaceContainerLow,
    );

    final backgroundColor = switch (tone) {
      KickPanelTone.soft => scheme.surfaceContainerLowest.withValues(alpha: 0.96),
      KickPanelTone.accent => Color.alphaBlend(
        scheme.primary.withValues(alpha: 0.055),
        neutralSurface,
      ),
      KickPanelTone.outline => scheme.surfaceContainerLowest.withValues(alpha: 0.88),
      KickPanelTone.muted => neutralSurface.withValues(alpha: 0.94),
    };

    final borderColor = switch (tone) {
      KickPanelTone.soft => scheme.outlineVariant.withValues(alpha: 0.26),
      KickPanelTone.accent => scheme.outlineVariant.withValues(alpha: 0.32),
      KickPanelTone.outline => scheme.outlineVariant.withValues(alpha: 0.46),
      KickPanelTone.muted => scheme.outlineVariant.withValues(alpha: 0.24),
    };

    final shadows = switch (tone) {
      KickPanelTone.accent => [
        BoxShadow(
          color: scheme.shadow.withValues(alpha: 0.045),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
      KickPanelTone.soft => [
        BoxShadow(
          color: scheme.shadow.withValues(alpha: 0.035),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
      _ => const <BoxShadow>[],
    };

    return AnimatedContainer(
      duration: context.kickTokens.shortDuration,
      curve: context.kickTokens.standardCurve,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(resolvedRadius),
        border: Border.all(color: borderColor),
        boxShadow: shadows,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class KickBadge extends StatelessWidget {
  const KickBadge({super.key, required this.label, this.leading, this.emphasis = false, this.tint});

  final String label;
  final Widget? leading;
  final bool emphasis;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = tint ?? scheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: emphasis
            ? Color.alphaBlend(tone.withValues(alpha: 0.12), scheme.surfaceContainerHigh)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(context.kickTokens.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            IconTheme(
              data: IconThemeData(size: 16, color: emphasis ? tone : scheme.onSurfaceVariant),
              child: leading!,
            ),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: emphasis ? tone : scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.alignment = SectionHeadingAlignment.start,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final SectionHeadingAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isCentered = alignment == SectionHeadingAlignment.center;
    final isEnd = alignment == SectionHeadingAlignment.end;

    final heading = Column(
      crossAxisAlignment: isCentered
          ? CrossAxisAlignment.center
          : isEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          textAlign: isCentered
              ? TextAlign.center
              : isEnd
              ? TextAlign.end
              : TextAlign.start,
          style: isCentered ? textTheme.displaySmall : textTheme.headlineLarge,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              subtitle!,
              textAlign: isCentered
                  ? TextAlign.center
                  : isEnd
                  ? TextAlign.end
                  : TextAlign.start,
              style: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );

    if (isCentered) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          heading,
          if (trailing != null) ...[const SizedBox(height: 18), trailing!],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = trailing != null && constraints.maxWidth < 680;
        if (!compact) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isEnd && trailing != null) ...[trailing!, const SizedBox(width: 16)],
              Expanded(
                child: Align(
                  alignment: isEnd
                      ? AlignmentDirectional.centerEnd
                      : AlignmentDirectional.centerStart,
                  child: heading,
                ),
              ),
              if (!isEnd && trailing != null) ...[const SizedBox(width: 16), trailing!],
            ],
          );
        }

        return Column(
          crossAxisAlignment: isEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            heading,
            if (trailing != null) ...[const SizedBox(height: 16), trailing!],
          ],
        );
      },
    );
  }
}

enum SectionHeadingAlignment { start, center, end }

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({super.key, required this.title, this.message, this.action, this.icon});

  final String title;
  final String? message;
  final Widget? action;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return KickPanel(
      tone: KickPanelTone.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
          ],
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (message?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}
