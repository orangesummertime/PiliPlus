import 'dart:io' show Platform;

import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoEndEdgeBackGesture;
import 'package:flutter/services.dart' show HapticFeedback;

/// Back by swiping from the right screen edge towards the left (iOS).
///
/// The gesture itself lives in the patched `cupertino_ui` next to the regular
/// iOS back swipe (lib/scripts/cupertino/end_edge_back_gesture.patch), so it
/// shares its behavior: the page follows the finger and reveals the previous
/// page, and the route only pops on release (past half way, or with a fling).
abstract final class EndEdgeBackGesture {
  static void init() {
    // tick when crossing the point where releasing would go back
    CupertinoEndEdgeBackGesture.onWillPopChanged = _onWillPopChanged;
    // confirm the pop on release
    CupertinoEndEdgeBackGesture.onPop = HapticFeedback.mediumImpact;
    setEnabled(Pref.endEdgeBackGesture);
  }

  static void setEnabled(bool value) {
    CupertinoEndEdgeBackGesture.enabled = Platform.isIOS && value;
  }

  static void _onWillPopChanged(bool willPop) {
    HapticFeedback.selectionClick();
  }
}
