import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/account_profile.dart';

const _geminiProviderIconAssetPath = 'assets/icons/providers/gemini.svg';
const _geminiProviderBrandIconAssetPath = 'assets/icons/providers/gemini_brand.png';
const _kiroProviderIconAssetPath = 'assets/icons/providers/kiro.svg';
const _kiroProviderBrandIconAssetPath = 'assets/icons/providers/kiro_brand.png';

enum ProviderIconVariant { monochrome, brand }

class ProviderIcon extends StatelessWidget {
  const ProviderIcon({
    super.key,
    required this.provider,
    this.size,
    this.color,
    this.variant = ProviderIconVariant.monochrome,
  });

  final AccountProvider provider;
  final double? size;
  final Color? color;
  final ProviderIconVariant variant;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final resolvedSize = size ?? iconTheme.size ?? 24;
    final resolvedColor = color ?? iconTheme.color ?? scheme.onSurfaceVariant;

    return switch (provider) {
      AccountProvider.gemini =>
        variant == ProviderIconVariant.brand
            ? Image.asset(
                _geminiProviderBrandIconAssetPath,
                width: resolvedSize,
                height: resolvedSize,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                filterQuality: FilterQuality.high,
              )
            : SvgPicture.asset(
                _geminiProviderIconAssetPath,
                width: resolvedSize,
                height: resolvedSize,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                theme: SvgTheme(currentColor: resolvedColor),
              ),
      AccountProvider.kiro =>
        variant == ProviderIconVariant.brand
            ? Image.asset(
                _kiroProviderBrandIconAssetPath,
                width: resolvedSize,
                height: resolvedSize,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                filterQuality: FilterQuality.high,
              )
            : SvgPicture.asset(
                _kiroProviderIconAssetPath,
                width: resolvedSize,
                height: resolvedSize,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                colorMapper: _KiroIconColorMapper(
                  bodyColor: resolvedColor,
                  eyeColor: _providerEyeColor(resolvedColor),
                ),
              ),
      AccountProvider.luma => _LumaProviderIcon(
        size: resolvedSize,
        color: resolvedColor,
        variant: variant,
      ),
    };
  }
}

/// Code-drawn placeholder icon for Luma. Replace with an SVG/brand asset when
/// the official icon ships with the rest of the Luma integration.
class _LumaProviderIcon extends StatelessWidget {
  const _LumaProviderIcon({required this.size, required this.color, required this.variant});

  final double size;
  final Color color;
  final ProviderIconVariant variant;

  @override
  Widget build(BuildContext context) {
    if (variant == ProviderIconVariant.brand) {
      final scheme = Theme.of(context).colorScheme;
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary, scheme.tertiary],
          ),
          borderRadius: BorderRadius.circular(size * 0.22),
        ),
        alignment: Alignment.center,
        child: Icon(Symbols.bolt_rounded, color: scheme.onPrimary, size: size * 0.62),
      );
    }
    return Icon(Symbols.bolt_rounded, color: color, size: size);
  }
}

Color _providerEyeColor(Color bodyColor) {
  return ThemeData.estimateBrightnessForColor(bodyColor) == Brightness.dark
      ? Colors.white
      : Colors.black;
}

class _KiroIconColorMapper extends ColorMapper {
  const _KiroIconColorMapper({required this.bodyColor, required this.eyeColor});

  final Color bodyColor;
  final Color eyeColor;

  @override
  Color substitute(String? id, String elementName, String attributeName, Color color) {
    if (attributeName != 'fill') {
      return color;
    }

    return switch (color.toARGB32()) {
      0xFFFFFFFF => bodyColor,
      0xFF000000 => eyeColor,
      _ => color,
    };
  }
}
