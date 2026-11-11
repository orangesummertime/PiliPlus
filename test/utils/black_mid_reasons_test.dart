import 'dart:io';

import 'package:PiliPlus/pages/common/reply/black_mid_badge.dart';
import 'package:PiliPlus/utils/black_mid_reasons.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('piliplus-reasons-');
    Hive.init(dir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
  });

  // no Hive.close(): after a widget test it never completes here
  tearDownAll(() => dir.delete(recursive: true));

  test('本地原因：可设置、清除，并持久化', () {
    BlackMidReasons.setLocal(1, '  手动  ');
    BlackMidReasons.setLocal(2, '');
    expect(BlackMidReasons.of(1), (reason: '手动', url: null));
    expect(BlackMidReasons.of(2), isNull);
    expect(GStorage.localCache.get('blackMidReasons'), {1: '手动'});

    BlackMidReasons.setLocal(1, null);
    expect(BlackMidReasons.of(1), isNull);
    expect(GStorage.localCache.get('blackMidReasons'), isEmpty);
  });

  testWidgets('已拉黑 旁的图标点开显示原因和加白按钮；只在账号里拉黑的没有图标', (tester) async {
    BlackMidReasons.setLocal(3, '刷屏');
    GlobalData().blackMids.addAll({3, 4});
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              BlackMidBadge(mid: 3), // local, with a reason
              BlackMidBadge(mid: 4), // local, no reason
              BlackMidBadge(mid: 2), // not blocked here (account only)
            ],
          ),
        ),
      ),
    );
    expect(find.text('已拉黑'), findsNWidgets(3));
    expect(find.byIcon(Icons.info_outline), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('拉黑原因'), findsOneWidget);
    expect(find.text('刷屏'), findsOneWidget);
    expect(find.text('来源：本地黑名单'), findsOneWidget);
    expect(find.text('加入白名单'), findsOneWidget);
  });

  testWidgets('资料卡标记：本地 / 云端 / 白名单，变化时即时更新', (tester) async {
    // mid 3, 4 are on the local blacklist (set above)
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MidListStatusPill(mid: 3),
              MidListStatusPill(mid: 99), // on no list
            ],
          ),
        ),
      ),
    );
    expect(find.text('本地黑名单'), findsOneWidget);
    expect(find.byIcon(Icons.block_rounded), findsOneWidget);

    GlobalData().whiteMids.add(3);
    GlobalData().midListsChanged();
    await tester.pump();
    expect(find.text('本地黑名单'), findsNothing);
    expect(find.text('白名单 · 已豁免'), findsOneWidget);
    expect(find.byIcon(Icons.verified_user_rounded), findsOneWidget);

    await tester.tap(find.text('白名单 · 已豁免'));
    await tester.pumpAndSettle();
    expect(find.text('· 本地黑名单'), findsOneWidget);
    expect(find.text('移出白名单'), findsOneWidget);

    GlobalData().whiteMids.remove(3);
    GlobalData().midListsChanged();
  });
}
