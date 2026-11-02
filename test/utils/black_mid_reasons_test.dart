import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/pages/common/reply/black_mid_badge.dart';
import 'package:PiliPlus/utils/black_mid_reasons.dart';
import 'package:PiliPlus/utils/black_mid_rules.dart';
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
    await GStorage.localCache.put(
      'blackMidRules',
      jsonEncode(
        [
          BlackMidRule(url: 'https://a', mids: [1, 2], reasons: {1: '规则A'}),
          BlackMidRule(
            url: 'https://b',
            mids: [1, 3],
            reasons: {1: '规则B', 3: '规则B3'},
          ),
        ].map((e) => e.toJson()).toList(),
      ),
    );
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('规则原因：同一 UID 取排在前面的规则', () {
    expect(BlackMidReasons.of(1), (reason: '规则A', url: 'https://a'));
    expect(BlackMidReasons.of(3), (reason: '规则B3', url: 'https://b'));
    expect(BlackMidReasons.of(2), isNull);
  });

  test('本地原因优先，可清除，并持久化', () {
    BlackMidReasons.setLocal(1, '  手动  ');
    BlackMidReasons.setLocal(2, '');
    expect(BlackMidReasons.of(1), (reason: '手动', url: null));
    expect(BlackMidReasons.of(2), isNull);
    expect(GStorage.localCache.get('blackMidReasons'), {1: '手动'});

    BlackMidReasons.setLocal(1, null);
    expect(BlackMidReasons.of(1), (reason: '规则A', url: 'https://a'));
    expect(GStorage.localCache.get('blackMidReasons'), isEmpty);
  });

  testWidgets('已拉黑 旁的图标点开显示原因；没有原因时只有标记', (tester) async {
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
    expect(find.text('规则B3'), findsOneWidget);
    expect(find.text('来源：在线规则 https://b'), findsOneWidget);
  });
}
