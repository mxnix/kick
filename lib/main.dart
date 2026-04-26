import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app/bootstrap_gate.dart';
import 'core/platform/desktop_runtime.dart';
import 'observability/glitchtip.dart';

Future<void> main(List<String> args) async {
  DesktopRuntime.configureLaunchOptions(DesktopLaunchOptions.fromArguments(args));

  await runKickWithGlitchTip(() async {
    final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
    if (Platform.isAndroid) {
      widgetsBinding.deferFirstFrame();
      FlutterForegroundTask.initCommunicationPort();
    }

    runApp(wrapWithGlitchTip(child: const KickBootstrapGate()));
  });
}
