import 'dart:convert';

import 'package:PiliPlus/utils/black_mid_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BlackMidRules.parse', () {
    test('每行一个或多个 UID，支持多种分隔符', () {
      expect(
        BlackMidRules.parse('1\n2 3\n4,5;6，7、8|9\r\n10'),
        {1, 2, 3, 4, 5, 6, 7, 8, 9, 10},
      );
    });

    test('注释与空行被忽略', () {
      expect(
        BlackMidRules.parse(
          '# 标题\n! adblock 风格\n// 注释\n\n123 # 广告号\n456 // 另一个\n',
        ),
        {123, 456},
      );
    });

    test('space 链接只取 UID，不误取查询参数里的数字', () {
      expect(
        BlackMidRules.parse(
          'https://space.bilibili.com/789?spm_id_from=333.999\n'
          'space.bilibili.com/1000/dynamic',
        ),
        {789, 1000},
      );
    });

    test('非纯数字、0 和超长数字被忽略', () {
      expect(
        BlackMidRules.parse('abc\n12a\n0\n99999999999999999999\n42'),
        {42},
      );
    });
  });

  group('BlackMidRules.parseWithReasons', () {
    test('行内 # 后面是原因，# 前不必有空格', () {
      final r = BlackMidRules.parseWithReasons(
        '123456 #广告号\n'
        '234567#刷屏\n'
        '345678 # 引战 带数字 999\n'
        '456789 // 另一种注释\n'
        '567890\n',
      );
      expect(r.mids, {123456, 234567, 345678, 456789, 567890});
      expect(r.reasons, {
        123456: '广告号',
        234567: '刷屏',
        345678: '引战 带数字 999',
        456789: '另一种注释',
      });
    });

    test('整行注释和空原因不算原因；同一行的多个 UID 共用原因', () {
      final r = BlackMidRules.parseWithReasons(
        '# 1111 标题\n'
        '1 2,3 # 同一批\n'
        '4 #\n'
        'https://space.bilibili.com/5?spm_id_from=x #链接也行\n',
      );
      expect(r.mids, {1, 2, 3, 4, 5});
      expect(r.reasons, {1: '同一批', 2: '同一批', 3: '同一批', 5: '链接也行'});
    });

    test('同一 UID 出现多次时保留第一个原因', () {
      final r = BlackMidRules.parseWithReasons('7 #先\n7 #后\n');
      expect(r.reasons, {7: '先'});
    });

    test('原因随规则一起保存和读取', () {
      final rule = BlackMidRule(url: 'a', mids: [1, 2], reasons: {1: '原因'});
      final back = BlackMidRule.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(jsonEncode(rule.toJson())) as Map,
        ),
      );
      expect(back.reasons, {1: '原因'});
      expect(BlackMidRule(url: 'b').toJson().containsKey('reasons'), isFalse);
    });

    test('apply 更新规则的原因', () {
      final rule = BlackMidRule(url: 'a');
      BlackMidRules.apply(rule, {1, 2}, [rule], {}, reasons: {2: 'x'});
      expect(rule.reasons, {2: 'x'});
      BlackMidRules.apply(rule, {1}, [rule], {});
      expect(rule.reasons, isEmpty);
    });
  });

  group('BlackMidRules.apply / release', () {
    test('只记录自己新增的 UID，不接管已有的', () {
      final blackMids = {1}; // 手动添加的
      final rule = BlackMidRule(url: 'a');
      final added = BlackMidRules.apply(rule, {1, 2, 3}, [rule], blackMids);
      expect(added, 2);
      expect(blackMids, {1, 2, 3});
      expect(rule.owned.toSet(), {2, 3});
      expect(rule.mids.toSet(), {1, 2, 3});
    });

    test('更新后从列表消失的 UID 被收回，手动添加的保留', () {
      final blackMids = {1};
      final rule = BlackMidRule(url: 'a');
      final rules = [rule];
      BlackMidRules.apply(rule, {1, 2, 3}, rules, blackMids);
      BlackMidRules.apply(rule, {3, 4}, rules, blackMids);
      expect(blackMids, {1, 3, 4});
      expect(rule.owned.toSet(), {3, 4});
    });

    test('删除规则时，另一规则也列出的 UID 保留并转移归属', () {
      final blackMids = <int>{};
      final a = BlackMidRule(url: 'a');
      final b = BlackMidRule(url: 'b');
      final rules = [a, b];
      BlackMidRules.apply(a, {1, 2}, rules, blackMids);
      BlackMidRules.apply(b, {2, 3}, rules, blackMids);
      expect(b.owned.toSet(), {3}); // 2 已由 a 添加

      BlackMidRules.release(a, rules, blackMids);
      rules.remove(a);
      expect(blackMids, {2, 3});
      expect(b.owned.toSet(), {2, 3});

      BlackMidRules.release(b, rules, blackMids);
      expect(blackMids, isEmpty);
    });
  });

  test('normalizeUrl 只接受 http(s)', () {
    expect(
      BlackMidRules.normalizeUrl(' https://a.com/x.txt '),
      'https://a.com/x.txt',
    );
    expect(BlackMidRules.normalizeUrl('ftp://a.com/x.txt'), isNull);
    expect(BlackMidRules.normalizeUrl('not a url'), isNull);
  });
}
