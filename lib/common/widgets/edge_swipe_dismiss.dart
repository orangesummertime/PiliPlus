import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoEndEdgeBackGesture;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:material_ui/material_ui.dart';

/// Shows a modal bottom sheet that can also be closed by swiping in from a
/// screen edge, like the comment panels: the left edge on iOS (the back
/// swipe) and the right edge when 右侧边缘返回手势 is on. The sheet follows
/// the finger down, gives the same haptics when armed, and closes on
/// release once armed.
Future<T?> showEdgeSwipeModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useSafeArea = false,
  bool isScrollControlled = false,
  BoxConstraints? constraints,
}) {
  final controller = BottomSheet.createAnimationController(
    Navigator.of(context),
  );
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: useSafeArea,
    isScrollControlled: isScrollControlled,
    constraints: constraints,
    transitionAnimationController: controller,
    sheetAnimationStyle: const AnimationStyle(
      curve: EdgeSwipeDismiss.curve,
      reverseCurve: EdgeSwipeDismiss.curve,
    ),
    builder: (context) => EdgeSwipeDismiss(
      controller: controller,
      child: builder(context),
    ),
  ).whenComplete(() {
    // the route does not own a controller passed in; dispose it once the
    // closing animation is over and the route is gone
    void dispose() => SchedulerBinding.instance.addPostFrameCallback(
      (_) => controller.dispose(),
    );
    if (controller.isDismissed) {
      dispose();
    } else {
      void listener(AnimationStatus status) {
        if (status.isDismissed) {
          controller.removeStatusListener(listener);
          dispose();
        }
      }

      controller.addStatusListener(listener);
    }
  });
}

class EdgeSwipeDismiss extends StatefulWidget {
  const EdgeSwipeDismiss({
    super.key,
    required this.controller,
    required this.child,
  });

  /// The sheet's transition controller (1 = fully open).
  final AnimationController controller;
  final Widget child;

  /// How close to a screen edge a swipe has to start.
  static const double edgeWidth = 24;

  /// The sheet's open/close curve (the material default, set explicitly so
  /// the drag can undo it and track the finger linearly).
  static const Curve curve = Easing.legacyDecelerate;

  /// The controller value at which the curved sheet shows [fraction].
  static double controllerValueFor(double fraction) {
    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      if (curve.transform(mid) < fraction) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }

  @override
  State<EdgeSwipeDismiss> createState() => _EdgeSwipeDismissState();
}

class _EdgeSwipeDismissState extends State<EdgeSwipeDismiss> {
  /// +1: from the left edge, -1: from the right edge, null: not tracking
  int? _direction;
  double _startX = 0;
  double _width = 1;
  bool _armed = false;

  static bool get _leftEnabled => defaultTargetPlatform == TargetPlatform.iOS;
  static bool get _rightEnabled => CupertinoEndEdgeBackGesture.enabled;

  void _onDown(DragDownDetails details) {
    _width = MediaQuery.sizeOf(context).width;
    final x = details.globalPosition.dx;
    _startX = x;
    if (_leftEnabled && x <= EdgeSwipeDismiss.edgeWidth) {
      _direction = 1;
    } else if (_rightEnabled && x >= _width - EdgeSwipeDismiss.edgeWidth) {
      _direction = -1;
    } else {
      _direction = null;
    }
  }

  void _setArmed(bool armed) {
    if (_armed == armed) return;
    _armed = armed;
    CupertinoEndEdgeBackGesture.onArmedChanged?.call(armed);
  }

  void _onUpdate(DragUpdateDetails details) {
    final direction = _direction;
    if (direction == null) return;
    final distance = ((details.globalPosition.dx - _startX) * direction).clamp(
      0.0,
      _width,
    );
    widget.controller.value = EdgeSwipeDismiss.controllerValueFor(
      1 - distance / _width,
    );
    _setArmed(distance >= CupertinoEndEdgeBackGesture.armDistance(_width));
  }

  void _onEnd([DragEndDetails? _]) {
    if (_direction == null) return;
    _direction = null;
    if (_armed) {
      _armed = false;
      Navigator.of(context).pop();
    } else {
      widget.controller.animateTo(
        1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  /// Only pointers that go down at an enabled edge take part, so drags
  /// anywhere else in the sheet are left to its content.
  bool _isEdge(PointerEvent event) {
    final width = MediaQuery.sizeOf(context).width;
    final x = event.position.dx;
    return (_leftEnabled && x <= EdgeSwipeDismiss.edgeWidth) ||
        (_rightEnabled && x >= width - EdgeSwipeDismiss.edgeWidth);
  }

  @override
  Widget build(BuildContext context) {
    if (!_leftEnabled && !_rightEnabled) return widget.child;
    return RawGestureDetector(
      behavior: .translucent,
      gestures: {
        _EdgeDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_EdgeDragGestureRecognizer>(
              () => _EdgeDragGestureRecognizer(debugOwner: this),
              (instance) => instance
                ..isEdge = _isEdge
                ..onDown = _onDown
                ..onUpdate = _onUpdate
                ..onEnd = _onEnd
                ..onCancel = _onEnd,
            ),
      },
      child: widget.child,
    );
  }
}

class _EdgeDragGestureRecognizer extends HorizontalDragGestureRecognizer {
  _EdgeDragGestureRecognizer({super.debugOwner});

  late bool Function(PointerEvent event) isEdge;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      isEdge(event) && super.isPointerAllowed(event);
}
