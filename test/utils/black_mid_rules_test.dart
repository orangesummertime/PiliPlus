import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/utils/black_mid_reasons.dart';
import 'package:PiliPlus/utils/black_mid_rules.dart';
import 'package:PiliPlus/utils/black_mid_store.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

const _fixtures = 'test/fixtures/black_mid_incremental';

/// Serves [files] (path → bytes); records requests; supports ETag.
class _Server {
  _Server._(this._server);

  final HttpServer _server;
  final files = <String, List<int>>{};
  final etags = <String, String>{};
  final requests = <String>[];

  static Future<_Server> start() async {
    final s = _Server._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    s._server.listen((req) {
      final p = req.uri.path;
      s.requests.add(
        req.headers.value('if-none-match') == null ? p : '$p (conditional)',
      );
      final body = s.files[p];
      if (body == null) {
        req.response.statusCode = 404;
      } else if (s.etags[p] case final etag?
          when req.headers.value('if-none-match') == etag) {
        req.response.statusCode = 304;
      } else {
        if (s.etags[p] case final etag?) req.response.headers.set('etag', etag);
        req.response.add(body);
      }
      req.response.close();
    });
    return s;
  }

  String url(String p) => 'http://127.0.0.1:${_server.port}$p';

  Future<void> close() => _server.close(force: true);
}

List<int> _fixture(String name) => File('$_fixtures/$name').readAsBytesSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() async {
    HttpOverrides.global = null;
    dir = await Directory.systemTemp.createTemp('piliplus-rules-');
    Hive.init(dir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
    BlackMidRules.debugStoreDir = '${dir.path}/rules';
  });

  setUp(() async {
    BlackMidRules.debugReset();
    await GStorage.localCache.clear();
    GlobalData().blackMids.clear();
    GlobalData().whiteMids.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  group('解析', () {
    test('txt：多种分隔符、注释、space 链接', () {
      expect(
        BlackMidRules.parse('1\n2 3\n4,5;6，7、8|9\r\n10'),
        {1, 2, 3, 4, 5, 6, 7, 8, 9, 10},
      );
      expect(
        BlackMidRules.parse(
          '# 标题\n! 注释\n// 注释\n\n123 # 广告号\n'
          'https://space.bilibili.com/789?spm_id_from=333.999\n'
          'abc\n0\n99999999999999999999\n',
        ),
        {123, 789},
      );
    });

    test('txt：# 后是原因，# 前不必有空格，同一行共用', () {
      final r = BlackMidRules.parseWithReasons(
        '123456 #广告号\n234567#刷屏\n1 2,3 # 同一批\n4 #\n# 9 标题\n',
      );
      expect(r.mids, {123456, 234567, 1, 2, 3, 4});
      expect(r.reasons, {
        123456: '广告号',
        234567: '刷屏',
        1: '同一批',
        2: '同一批',
        3: '同一批',
      });
    });

    test('差量：+ 新增或改原因，- 移除；非法行报错', () {
      final d = BlackMidRules.parseDelta('+1 #甲\n+2\n-3\n\n+4 #带 # 号\n');
      expect(d.adds, {1: '甲', 2: null, 4: '带 # 号'});
      expect(d.removes, {3});
      expect(() => BlackMidRules.parseDelta('1\n'), throwsFormatException);
      expect(() => BlackMidRules.parseDelta('+abc\n'), throwsFormatException);
      expect(() => BlackMidRules.parseDelta('-0\n'), throwsFormatException);
    });

    test('normalizeUrl 只接受 http(s)', () {
      expect(
        BlackMidRules.normalizeUrl(' https://a.com/x.txt '),
        'https://a.com/x.txt',
      );
      expect(BlackMidRules.normalizeUrl('ftp://a.com/x.txt'), isNull);
      expect(BlackMidRules.normalizeUrl('not a url'), isNull);
    });
  });

  group('BlackMidStore', () {
    test('查找、原因、合并差量、存取', () {
      final store = BlackMidStore.build(
        {5, 1, 9, 3},
        {1: '甲', 9: '乙', 3: '甲'},
      );
      expect(store.length, 4);
      expect([for (final (m, _) in store.entries) m], [1, 3, 5, 9]);
      expect(store.contains(5), isTrue);
      expect(store.contains(4), isFalse);
      expect(store.reasonOf(3), '甲');
      expect(store.reasonOf(5), isNull);

      final next = store.apply({4: '丙', 9: null, 10: '甲'}, {1, 5});
      expect(
        [for (final e in next.entries) e],
        [
          (3, '甲'),
          (4, '丙'),
          (9, null),
          (10, '甲'),
        ],
      );

      final back = BlackMidStore.fromBytes(next.toBytes());
      expect(
        [for (final e in back.entries) e],
        [
          for (final e in next.entries) e,
        ],
      );
      expect(BlackMidStore.fromBytes(BlackMidStore.empty.toBytes()).length, 0);
      expect(
        () => BlackMidStore.fromBytes(Uint8List(20)),
        throwsFormatException,
      );
    });

    test('300 万条：构建、合并 10 万条、存取都在秒级', () {
      final mids = <int>{for (var i = 1; i <= 3000000; i++) i * 7919};
      final sw = Stopwatch()..start();
      final store = BlackMidStore.build(mids, {7919: '原因'});
      final next = store.apply(
        {for (var i = 1; i <= 100000; i++) i * 7919 + 1: '新增'},
        {7919 * 2},
      );
      expect(next.length, 3000000 + 100000 - 1);
      final bytes = next.toBytes();
      final back = BlackMidStore.fromBytes(bytes);
      expect(back.contains(7919 * 3 + 1), isTrue);
      expect(back.reasonOf(7919 * 5 + 1), '新增');
      expect(back.contains(7919 * 2), isFalse);
      expect(sw.elapsed, lessThan(const Duration(seconds: 15)));
      // ~12 bytes per UID
      expect(bytes.length, lessThan(3100000 * 13));
    });
  });

  group('增量订阅（Codex 联调样例）', () {
    late _Server server;
    setUp(() async {
      server = await _Server.start();
      for (final f in [
        'snapshot-1-b85b53719f4d8ce63bee.txt.gz',
        'snapshot-2-75759bb3bfaaef994e56.txt.gz',
        'delta-1-to-2-3ca36df4fb500984198b.txt.gz',
      ]) {
        server.files['/v1/$f'] = _fixture(f);
      }
    });
    tearDown(() => server.close());

    void publish(String manifest, {String? etag}) {
      server.files['/v1/manifest.json'] = _fixture(manifest);
      if (etag != null) server.etags['/v1/manifest.json'] = etag;
    }

    test('首次下载全量，之后只下差量；同版本不再下载', () async {
      publish('history/manifest-1.json', etag: '"m1"');
      final url = server.url('/v1/manifest.json');
      expect(await BlackMidRules.addAndUpdate([url]), contains('新增 3 个 UID'));
      final rule = BlackMidRules.rules.single;
      expect(rule.manifest, isTrue);
      expect(rule.version, 1);
      expect(rule.count, 3);
      expect(GlobalData().isBlackMid(345678), isTrue);
      expect(BlackMidReasons.of(234567)?.reason, '批量广告引流号');
      expect(BlackMidReasons.of(234567)?.url, url);

      // unchanged: 304 on the manifest, nothing else is fetched
      server.requests.clear();
      expect(await BlackMidRules.update(), '1 个规则无变化');
      expect(server.requests, ['/v1/manifest.json (conditional)']);

      publish('manifest.json', etag: '"m2"');
      server.requests.clear();
      expect(await BlackMidRules.update(), '更新 1 个规则，新增 1 个 UID，移除 1 个');
      expect(server.requests, [
        '/v1/manifest.json (conditional)',
        '/v1/delta-1-to-2-3ca36df4fb500984198b.txt.gz',
      ]);
      expect(rule.version, 2);
      expect(GlobalData().isBlackMid(345678), isFalse);
      expect(GlobalData().isBlackMid(456789), isTrue);
      expect(BlackMidReasons.of(234567)?.reason, '引战');
      // the manual blacklist is untouched
      expect(GlobalData().blackMids, isEmpty);

      // the store survives a restart
      BlackMidRules.debugReset();
      await BlackMidRules.init();
      expect(BlackMidRules.rules.single.version, 2);
      expect(GlobalData().isBlackMid(456789), isTrue);
      expect(BlackMidReasons.of(456789)?.reason, '刷屏');
    });

    test('本地版本太旧或差量对不上：回退下载全量', () async {
      publish('history/manifest-1.json');
      await BlackMidRules.addAndUpdate([server.url('/v1/manifest.json')]);

      // the delta is broken
      server.files['/v1/delta-1-to-2-3ca36df4fb500984198b.txt.gz'] = utf8
          .encode('oops\n');
      publish('manifest.json');
      server.requests.clear();
      await BlackMidRules.update();
      expect(
        server.requests.last,
        '/v1/snapshot-2-75759bb3bfaaef994e56.txt.gz',
      );
      expect(BlackMidRules.rules.single.version, 2);
      expect(GlobalData().isBlackMid(456789), isTrue);
      expect(GlobalData().isBlackMid(345678), isFalse);
    });

    test('快照条数与清单不符：报错，保留原数据', () async {
      publish('history/manifest-1.json');
      await BlackMidRules.addAndUpdate([server.url('/v1/manifest.json')]);
      final m = jsonDecode(utf8.decode(_fixture('manifest.json')))
        ..['count'] = 99
        ..['deltas'] = {};
      server.files['/v1/manifest.json'] = utf8.encode(jsonEncode(m));
      expect(await BlackMidRules.update(), '1 个失败');
      final rule = BlackMidRules.rules.single;
      expect(rule.error, contains('校验失败'));
      expect(rule.version, 1);
      expect(GlobalData().isBlackMid(345678), isTrue);
    });
  });

  group('txt 订阅', () {
    late _Server server;
    setUp(() async => server = await _Server.start());
    tearDown(() => server.close());

    test('ETag 304 或内容没变：跳过；删除规则后不再屏蔽', () async {
      server.files['/uids.txt'] = utf8.encode('1 #甲\n2\n');
      server.etags['/uids.txt'] = '"a"';
      final url = server.url('/uids.txt');
      await BlackMidRules.addAndUpdate([url]);
      expect(GlobalData().isBlackMid(1), isTrue);
      expect(BlackMidReasons.of(1)?.reason, '甲');

      server.requests.clear();
      expect(await BlackMidRules.update(), '1 个规则无变化');
      expect(server.requests, ['/uids.txt (conditional)']);

      // no validators, same content
      server.etags.clear();
      expect(await BlackMidRules.update(), '1 个规则无变化');

      server.files['/uids.txt'] = utf8.encode('2\n3\n');
      expect(
        await BlackMidRules.update(),
        '更新 1 个规则，新增 1 个 UID，移除 1 个',
      );
      expect(GlobalData().isBlackMid(1), isFalse);
      expect(GlobalData().isBlackMid(3), isTrue);

      await BlackMidRules.remove(url);
      expect(GlobalData().isBlackMid(3), isFalse);
      expect(BlackMidRules.rules, isEmpty);
    });
  });

  test('旧版数据迁移：规则添加的 UID 移出本地黑名单，手动的保留', () async {
    GlobalData().blackMids.addAll({1, 2, 3, 100});
    await GStorage.localCache.put(
      'blackMidRules',
      jsonEncode([
        {
          'url': 'https://a/uids.txt',
          'mids': [1, 2, 3],
          'owned': [2, 3], // 1 was in the blacklist before
          'reasons': {'2': '旧原因'},
          'updatedAt': 1000,
        },
      ]),
    );
    await BlackMidRules.init();
    expect(GlobalData().blackMids, {1, 100});
    expect(GStorage.localCache.get(LocalCacheKey.blackMids), {1, 100});
    final rule = BlackMidRules.rules.single;
    expect(rule.count, 3);
    expect(GlobalData().isBlackMid(3), isTrue);
    expect(BlackMidReasons.of(2)?.reason, '旧原因');
    expect(
      jsonDecode(GStorage.localCache.get('blackMidRules') as String).single,
      isNot(contains('mids')),
    );
  });

  group('白名单', () {
    late _Server server;
    setUp(() async => server = await _Server.start());
    tearDown(() => server.close());

    test('优先于本地黑名单和在线规则；手动拉黑会移出白名单', () async {
      server.files['/uids.txt'] = utf8.encode('1\n2\n');
      await BlackMidRules.addAndUpdate([server.url('/uids.txt')]);
      Pref.setBlackMid(3);
      expect([1, 2, 3].map(GlobalData().isBlackMid), [true, true, true]);

      Pref.setWhiteMid(1);
      Pref.setWhiteMid(3);
      expect([1, 2, 3].map(GlobalData().isBlackMid), [false, true, false]);
      expect(GStorage.localCache.get(LocalCacheKey.whiteMids), {1, 3});
      // the blacklist itself is kept
      expect(GlobalData().blackMids, {3});

      Pref.setBlackMid(1);
      expect(GlobalData().whiteMids, {3});
      expect(GlobalData().isBlackMid(1), isTrue);

      Pref.removeWhiteMid(3);
      expect(GlobalData().isBlackMid(3), isTrue);
    });
  });
}
