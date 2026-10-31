// Requires the patched cupertino_ui (lib/scripts/cupertino/end_edge_back_gesture.patch).
import 'package:PiliPlus/common/widgets/edge_swipe_dismiss.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoEndEdgeBackGesture;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _size = Size(400, 800); // arm distance: 80

Future<void> _openSheet(WidgetTester tester) async {
  tester.view
    ..physicalSize = _size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showEdgeSwipeModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => const SizedBox(
                height: 600,
                width: double.infinity,
                child: Center(child: Text('sheet')),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

double _sheetTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(BottomSheet)).dy;

Future<TestGesture> _drag(WidgetTester tester, double fromX, double dx) async {
  final gesture = await tester.startGesture(Offset(fromX, 500));
  final steps = (dx.abs() / 10).ceil();
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(dx / steps, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  return gesture;
}

void main() {
  final armed = <bool>[];

  setUp(() {
    armed.clear();
    CupertinoEndEdgeBackGesture.enabled = true;
    CupertinoEndEdgeBackGesture.onArmedChanged = armed.add;
  });

  tearDown(() {
    CupertinoEndEdgeBackGesture.enabled = false;
    CupertinoEndEdgeBackGesture.onArmedChanged = null;
  });

  testWidgets(
    '从右边缘滑：面板跟手下移，没拖够弹回，拖够松手关闭',
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    (tester) async {
      await _openSheet(tester);
      final top = _sheetTop(tester);

      var gesture = await _drag(tester, 395, -40);
      // 40 of 400 px: the 600 px sheet is 10% down
      expect(_sheetTop(tester), closeTo(top + 60, 3), reason: 'follows');
      expect(armed, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_sheetTop(tester), top, reason: 'springs back');

      gesture = await _drag(tester, 395, -100);
      expect(armed, [true]);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('sheet'), findsNothing);
    },
  );

  testWidgets(
    'iOS 从左边缘滑也能关闭',
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    (tester) async {
      await _openSheet(tester);
      final gesture = await _drag(tester, 5, 100);
      expect(armed, [true]);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('sheet'), findsNothing);
    },
  );

  testWidgets(
    '不是从边缘开始的横滑不处理；右侧开关关闭时右边缘无效',
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    (tester) async {
      await _openSheet(tester);
      final top = _sheetTop(tester);
      var gesture = await _drag(tester, 200, 150);
      expect(_sheetTop(tester), top);
      await gesture.up();
      await tester.pumpAndSettle();

      CupertinoEndEdgeBackGesture.enabled = false;
      gesture = await _drag(tester, 395, -150);
      expect(_sheetTop(tester), top);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('sheet'), findsOneWidget);
      expect(armed, isEmpty);
    },
  );
}
