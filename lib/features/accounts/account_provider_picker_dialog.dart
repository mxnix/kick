import 'package:flutter/material.dart';

import '../../core/theme/kick_icons.dart';
import '../../data/models/account_profile.dart';
import '../../l10n/kick_localizations.dart';
import '../shared/kick_actions.dart';
import '../shared/provider_icon.dart';

sealed class AccountProviderPickerResult {
  const AccountProviderPickerResult();
}

class AccountProviderPickerSelected extends AccountProviderPickerResult {
  const AccountProviderPickerSelected(this.provider);
  final AccountProvider provider;
}

class AccountProviderPickerImportFromFile extends AccountProviderPickerResult {
  const AccountProviderPickerImportFromFile();
}

Future<AccountProviderPickerResult?> showAccountProviderPickerDialog(BuildContext context) {
  return showDialog<AccountProviderPickerResult>(
    context: context,
    builder: (context) => const _AccountProviderPickerDialog(),
  );
}

class _AccountProviderPickerDialog extends StatelessWidget {
  const _AccountProviderPickerDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final stacked = constraints.maxWidth < 320;
              final cardSpacing = compact ? 12.0 : 28.0;
              final cardWidth = stacked
                  ? constraints.maxWidth
                  : compact
                  ? ((constraints.maxWidth - cardSpacing) / 2).clamp(148.0, 172.0)
                  : 228.0;
              final cardAspectRatio = compact ? 0.88 : 228 / 296;
              final titleStyle = textTheme.displaySmall?.copyWith(
                fontSize: compact ? 28 : 40,
                fontWeight: FontWeight.w400,
                color: scheme.onSurface,
                height: 1,
              );

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: compact ? 290 : 420),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        l10n.connectAccountProviderPickerTitle,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: titleStyle,
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 16 : 36),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: cardSpacing,
                    runSpacing: cardSpacing,
                    children: [
                      _ProviderChoiceCard(
                        provider: AccountProvider.kiro,
                        width: cardWidth,
                        aspectRatio: cardAspectRatio,
                        labelStyle: _ProviderChoiceLabelStyle(
                          fontSize: compact ? 22 : 39,
                          iconSize: compact ? 62 : 82,
                          iconSlotHeight: compact ? 74 : 96,
                          labelGap: compact ? 18 : 34,
                          labelSlotHeight: compact ? 22 : 39,
                        ),
                      ),
                      _ProviderChoiceCard(
                        provider: AccountProvider.gemini,
                        width: cardWidth,
                        aspectRatio: cardAspectRatio,
                        labelStyle: _ProviderChoiceLabelStyle(
                          fontSize: compact ? 18 : 32,
                          iconSize: compact ? 62 : 82,
                          iconSlotHeight: compact ? 74 : 96,
                          labelGap: compact ? 18 : 34,
                          labelSlotHeight: compact ? 22 : 39,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 18 : 28),
                  KickSecondaryAction(
                    icon: KickIcons.fileUpload,
                    label: l10n.accountImportFromFileButton,
                    fullWidth: true,
                    variant: KickSecondaryActionVariant.text,
                    onPressed: () =>
                        Navigator.of(context).pop(const AccountProviderPickerImportFromFile()),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ProviderChoiceCard extends StatefulWidget {
  const _ProviderChoiceCard({
    required this.provider,
    required this.width,
    required this.aspectRatio,
    required this.labelStyle,
  });

  final AccountProvider provider;
  final double width;
  final double aspectRatio;
  final _ProviderChoiceLabelStyle labelStyle;

  @override
  State<_ProviderChoiceCard> createState() => _ProviderChoiceCardState();
}

class _ProviderChoiceCardState extends State<_ProviderChoiceCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = switch (widget.provider) {
      AccountProvider.gemini => context.l10n.accountProviderGeminiCli,
      AccountProvider.kiro => context.l10n.accountProviderKiro,
    };
    final highlighted = _hovered || _focused;
    final borderColor = highlighted
        ? scheme.outline.withValues(alpha: 0.82)
        : scheme.outlineVariant.withValues(alpha: 0.78);
    final radius = widget.width < 190 ? 34.0 : 46.0;
    final verticalPadding = widget.width < 190 ? 18.0 : 24.0;
    final horizontalPadding = widget.width < 190 ? 16.0 : 20.0;

    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: FocusableActionDetector(
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          child: Semantics(
            button: true,
            label: label,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(radius),
                onTap: () =>
                    Navigator.of(context).pop(AccountProviderPickerSelected(widget.provider)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  decoration: BoxDecoration(
                    color: highlighted
                        ? scheme.surfaceContainerLow.withValues(alpha: 0.82)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: borderColor),
                    boxShadow: highlighted
                        ? [
                            BoxShadow(
                              color: scheme.shadow.withValues(alpha: 0.08),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ]
                        : const [],
                  ),
                  child: AspectRatio(
                    aspectRatio: widget.aspectRatio,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: widget.labelStyle.iconSlotHeight,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: ProviderIcon(
                              provider: widget.provider,
                              size: widget.labelStyle.iconSize,
                              variant: ProviderIconVariant.brand,
                            ),
                          ),
                        ),
                        SizedBox(height: widget.labelStyle.labelGap),
                        SizedBox(
                          height: widget.labelStyle.labelSlotHeight,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                maxLines: 1,
                                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                  fontSize: widget.labelStyle.fontSize,
                                  fontWeight: FontWeight.w400,
                                  height: 1,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderChoiceLabelStyle {
  const _ProviderChoiceLabelStyle({
    required this.fontSize,
    required this.iconSize,
    required this.iconSlotHeight,
    required this.labelGap,
    required this.labelSlotHeight,
  });

  final double fontSize;
  final double iconSize;
  final double iconSlotHeight;
  final double labelGap;
  final double labelSlotHeight;
}
