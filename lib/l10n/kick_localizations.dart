import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

typedef KickLocalizations = AppLocalizations;

extension KickLocalizationsBuildContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

AppLocalizations lookupKickLocalizations([Locale locale = const Locale('ru')]) {
  return lookupAppLocalizations(locale);
}
