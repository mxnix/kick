import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app/bootstrap_gate.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    widgetsBinding.deferFirstFrame();
    FlutterForegroundTask.initCommunicationPort();
  }

  runApp(const KickBootstrapGate());
}
