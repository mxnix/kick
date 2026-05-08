import 'dart:async';

import 'package:flutter/services.dart';

class KickHaptics {
  const KickHaptics._();

  static void light() {
    unawaited(HapticFeedback.lightImpact());
  }

  static void selection() {
    unawaited(HapticFeedback.selectionClick());
  }
}
