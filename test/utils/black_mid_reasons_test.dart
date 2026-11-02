import 'dart:io';

import 'package:PiliPlus/pages/common/reply/black_mid_badge.dart';
import 'package:PiliPlus/utils/black_mid_reasons.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('piliplus-reasons-');
    Hive.init(dir.path);
    GStorage.localCache = await Hive.openBox('localCache');
  });

  // no Hive.close(): after a widget test it never completes here
  tearDownAll(() => dir.delete(recursive: true));

  test('本地原因：可设置、清除，并持久化', () async {
    BlackMidReasons.setLocal(1, '  手动  ');
    BlackMidReasons.setLocal(2, '');
    expect(BlackMidReasons.of(1), (reason: '手动', url: null));
    expect(BlackMidReasons.of(2), isNull);
    expect(GStorage.localCache.get('blackMidReasons'), {1: '手动'});

    BlackMidReasons.setLocal(1, null);
    expect(BlackMidReasons.of(1), isNull);
    expect(GStorage.localCache.get('blackMidReasons'), isEmpty);
  });

  testWidgets('已拉黑 旁的图标点开显示原因；没有原因时只有标记', (tester) async {
    BlackMidReasons.setLocal(3, '刷屏');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [BlackMidBadge(mid: 3), BlackMidBadge(mid: 2)],
          ),
        ),
      ),
    );
    expect(find.text('已拉黑'), findsNWidgets(2));
    expect(find.byIcon(Icons.info_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('拉黑原因'), findsOneWidget);
    expect(find.text('刷屏'), findsOneWidget);
    expect(find.text('来源：本地添加'), findsOneWidget);
  });
}
