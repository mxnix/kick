import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  final googleSans = FontLoader('KickGoogleSans')
    ..addFont(rootBundle.load('assets/fonts/google_sans/GoogleSans-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/google_sans/GoogleSans-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/google_sans/GoogleSans-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/google_sans/GoogleSans-Bold.ttf'));
  final materialSymbolsRounded =
      FontLoader('packages/material_symbols_icons/MaterialSymbolsRounded')..addFont(
        rootBundle.load('packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf'),
      );
  final materialSymbolsOutlined =
      FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')..addFont(
        rootBundle.load('packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'),
      );
  final materialSymbolsSharp = FontLoader(
    'packages/material_symbols_icons/MaterialSymbolsSharp',
  )..addFont(rootBundle.load('packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf'));

  await Future.wait([
    materialIcons.load(),
    googleSans.load(),
    materialSymbolsRounded.load(),
    materialSymbolsOutlined.load(),
    materialSymbolsSharp.load(),
  ]);
  await testMain();
}
