// Requires the patched cupertino_ui (lib/scripts/cupertino/end_edge_back_gesture.patch).
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(400, 800);

Future<void> _pumpTwoPages(WidgetTester tester) async {
  tester.view
    ..physicalSize = _size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    CupertinoApp(
      home: const Center(child: Text('first')),
      routes: {
        '/second': (_) => const ColoredBox(
          color: Color(0xFFFFFFFF),
          child: Center(child: Text('second')),
        ),
      },
    ),
  );
  tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/second');
  await tester.pumpAndSettle();
}

/// Left edge of the second page, in global coordinates.
double _secondPageLeft(WidgetTester tester) =>
    tester.getTopLeft(find.byType(ColoredBox).last).dx;

void main() {
  final willPopEvents = <bool>[];
  var pops = 0;

  setUp(() {
    willPopEvents.clear();
    pops = 0;
    CupertinoEndEdgeBackGesture.enabled = true;
    CupertinoEndEdgeBackGesture.onWillPopChanged = willPopEvents.add;
    CupertinoEndEdgeBackGesture.onPop = () => pops++;
  });

  tearDown(() {
    CupertinoEndEdgeBackGesture.enabled = false;
    CupertinoEndEdgeBackGesture.onWillPopChanged = null;
    CupertinoEndEdgeBackGesture.onPop = null;
  });

  testWidgets('页面跟手向左移动并露出上一页，过半松手返回', (tester) async {
    await _pumpTwoPages(tester);
    expect(find.text('first'), findsNothing);

    final gesture = await tester.startGesture(const Offset(395, 400));
    await gesture.moveBy(const Offset(-20, 0));
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();

    // previous page is laid out underneath (preview)
    expect(find.text('first'), findsOneWidget);
    // mirrored: the page moves left with the finger, not right
    final left = _secondPageLeft(tester);
    expect(left, lessThan(0));
    expect(left, greaterThan(-130));
    expect(pops, 0, reason: 'must not pop before release');
    expect(willPopEvents, isEmpty);

    await gesture.moveBy(const Offset(-150, 0));
    await tester.pump();
    expect(willPopEvents, [true], reason: 'tick when passing half way');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(pops, 1);
    expect(find.text('second'), findsNothing);
    expect(find.text('first'), findsOneWidget);
  });

  testWidgets('未过半慢慢松手则回弹，不返回', (tester) async {
    await _pumpTwoPages(tester);

    final gesture = await tester.startGesture(const Offset(395, 400));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-8, 0));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(pops, 0);
    expect(find.text('second'), findsOneWidget);
    expect(_secondPageLeft(tester), 0);
  });

  testWidgets('过半后又拖回再松手：回弹，并再次触感提示', (tester) async {
    await _pumpTwoPages(tester);

    final gesture = await tester.startGesture(const Offset(395, 400));
    await gesture.moveBy(const Offset(-20, 0));
    await gesture.moveBy(const Offset(-260, 0));
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(willPopEvents, [true, false]);
    expect(pops, 0);
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('快速向左甩动即使距离短也返回', (tester) async {
    await _pumpTwoPages(tester);
    await tester.flingFrom(const Offset(395, 400), const Offset(-120, 0), 1500);
    await tester.pumpAndSettle();
    expect(pops, 1);
    expect(find.text('second'), findsNothing);
  });

  testWidgets('关闭开关后右边缘无效，屏幕中间也不触发', (tester) async {
    await _pumpTwoPages(tester);

    CupertinoEndEdgeBackGesture.enabled = false;
    await tester.dragFrom(const Offset(395, 400), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);

    CupertinoEndEdgeBackGesture.enabled = true;
    await tester.dragFrom(const Offset(200, 400), const Offset(-190, 0));
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
    expect(pops, 0);
  });

  testWidgets('原有的左边缘返回不受影响', (tester) async {
    await _pumpTwoPages(tester);
    final gesture = await tester.startGesture(const Offset(5, 400));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    expect(_secondPageLeft(tester), greaterThan(0), reason: 'normal direction');
    await gesture.moveBy(const Offset(200, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);
    expect(pops, 0, reason: 'end edge callback not used');
  });

  testWidgets('首页不能右滑返回', (tester) async {
    tester.view
      ..physicalSize = _size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const CupertinoApp(home: Center(child: Text('first'))),
    );
    await tester.dragFrom(const Offset(395, 400), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
    expect(pops, 0);
  });
}
