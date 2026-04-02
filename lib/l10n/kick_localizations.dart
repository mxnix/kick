import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

typedef KickLocalizations = AppLocalizations;

Locale? _kickLocaleOverride;

extension KickLocalizationsBuildContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

void setKickLocaleOverride(Locale? locale) {
  _kickLocaleOverride = _normalizeKickLocale(locale);
}

Locale resolveKickLocale([Iterable<Locale>? preferredLocales]) {
  final override = _kickLocaleOverride;
  if (override != null) {
    return override;
  }

  final supportedLocales = AppLocalizations.supportedLocales;
  final dispatcher = _currentPlatformDispatcher();
  final candidates = (preferredLocales ?? dispatcher.locales).toList(growable: false);

  for (final candidate in candidates) {
    for (final supportedLocale in supportedLocales) {
      if (_matchesLocaleExactly(candidate, supportedLocale)) {
        return supportedLocale;
      }
    }
  }

  for (final candidate in candidates) {
    for (final supportedLocale in supportedLocales) {
      if (candidate.languageCode == supportedLocale.languageCode) {
        return supportedLocale;
      }
    }
  }

  return supportedLocales.first;
}

AppLocalizations lookupKickLocalizations([Locale? locale]) {
  return lookupAppLocalizations(locale ?? resolveKickLocale());
}

PlatformDispatcher _currentPlatformDispatcher() {
  try {
    return WidgetsBinding.instance.platformDispatcher;
  } catch (_) {
    return PlatformDispatcher.instance;
  }
}

bool _matchesLocaleExactly(Locale candidate, Locale supportedLocale) {
  final candidateScriptCode = candidate.scriptCode?.trim();
  final supportedScriptCode = supportedLocale.scriptCode?.trim();
  if (candidate.languageCode != supportedLocale.languageCode ||
      (candidateScriptCode?.isNotEmpty == true
          ? candidateScriptCode != supportedScriptCode
          : supportedScriptCode?.isNotEmpty == true)) {
    return false;
  }

  final candidateCountryCode = candidate.countryCode?.trim();
  final supportedCountryCode = supportedLocale.countryCode?.trim();
  if (candidateCountryCode?.isNotEmpty == true) {
    return candidateCountryCode == supportedCountryCode;
  }

  return supportedCountryCode?.isNotEmpty != true;
}

Locale? _normalizeKickLocale(Locale? locale) {
  if (locale == null) {
    return null;
  }

  for (final supportedLocale in AppLocalizations.supportedLocales) {
    if (locale.languageCode == supportedLocale.languageCode) {
      return supportedLocale;
    }
  }
  return null;
}
