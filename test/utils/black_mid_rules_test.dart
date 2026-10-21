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
