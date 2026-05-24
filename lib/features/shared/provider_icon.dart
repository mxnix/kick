import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/models/account_profile.dart';

const _geminiProviderIconAssetPath = 'assets/icons/providers/antigravity.svg';
const _geminiProviderBrandIconAssetPath = 'assets/icons/providers/antigravity_brand.png';
const _kiroProviderIconAssetPath = 'assets/icons/providers/kiro.svg';
const _kiroProviderBrandIconAssetPath = 'assets/icons/providers/kiro_brand.png';
const _lumaProviderIconAssetPath = 'assets/icons/providers/luma.svg';
const _lumaProviderBrandIconAssetPath = 'assets/icons/providers/luma_brand.png';

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
      AccountProvider.antigravity =>
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
      AccountProvider.luma =>
        variant == ProviderIconVariant.brand
            ? Image.asset(
                _lumaProviderBrandIconAssetPath,
                width: resolvedSize,
                height: resolvedSize,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                filterQuality: FilterQuality.high,
              )
            : SvgPicture.asset(
                _lumaProviderIconAssetPath,
                width: resolvedSize,
                height: resolvedSize,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                theme: SvgTheme(currentColor: resolvedColor),
              ),
    };
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
