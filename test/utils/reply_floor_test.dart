import 'dart:convert';
import 'dart:math';

import 'package:PiliPlus/utils/reply_floor.dart';
import 'package:flutter_test/flutter_test.dart';

/// A comment area with the semantics of the web API (verified against
/// bilibili): floors increase with time, deleted floors are skipped, and
/// query(cursor, ps) returns the newest `ps` comments with floor < cursor.
class _Area {
  _Area(int floors, {double deleted = 0, int seed = 1}) {
    final rnd = Random(seed);
    for (var f = 1; f <= floors; f++) {
      if (rnd.nextDouble() >= deleted) _add(f);
    }
  }

  final floorOf = <int, int>{}; // rpid -> floor
  final _visible = <int>[]; // floors, ascending
  int calls = 0;
  bool fail = false;

  void _add(int floor) {
    _visible.add(floor);
    floorOf[1000000 + floor] = floor;
  }

  int get top => _visible.last;

  /// Posts a new comment (next floor).
  void post() => _add(top + 1);

  Future<FloorChunk?> fetch(int? cursor, int ps) async {
    calls++;
    if (fail) return null;
    final below = _visible.reversed
        .where((f) => cursor == null || f < cursor)
        .take(ps)
        .toList();
    return FloorChunk(
      rpids: [for (final f in below) 1000000 + f],
      ctimes: [for (final f in below) 1700000000 + f * 60],
      lastFloor: below.isEmpty ? 0 : below.last,
      isEnd: below.isEmpty || below.last == _visible.first,
    );
  }

  List<int> newest(int n) => [
    for (final f in _visible.reversed.take(n)) 1000000 + f,
  ];
}

Future<void> _settle(ReplyFloorResolver r) async {
  for (var i = 0; i < 2000; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ReplyFloorResolver _resolver(_Area area) =>
    ReplyFloorResolver(fetch: area.fetch, minInterval: Duration.zero);

void main() {
  test('游标编码与网页接口一致', () {
    // captured from the web client: {1: 1, 6: {1: 160548}}
    expect(
      base64.decode(ReplyFloorHttp.encodeOffset(160548)),
      [0x08, 0x01, 0x32, 0x04, 0x08, 0xa4, 0xe6, 0x09],
    );
  });

  for (final (name, deleted) in [
    ('没有删除', 0.0),
    ('少量删除（几百条视频的实测比例）', 0.15),
    ('大量删除（大热视频）', 0.4),
  ]) {
    test('每条都准：$name', () async {
      final area = _Area(500, deleted: deleted, seed: 7);
      final r = _resolver(area);
      final shown = area.newest(60); // three pages scrolled
      for (final rpid in shown) {
        r.request(rpid, 1700000000 + area.floorOf[rpid]! * 60);
      }
      await _settle(r);
      for (final rpid in shown) {
        expect(r.floorOf(rpid), area.floorOf[rpid], reason: 'rpid $rpid');
      }
      // ignore: avoid_print
      print('$name: 60 条用了 ${area.calls} 次请求');
    });
  }

  test('没有删除时每 20 条只需 1 次请求（首页 2 次）', () async {
    final area = _Area(500);
    final r = _resolver(area);
    for (final rpid in area.newest(60)) {
      r.request(rpid, 1700000000 + area.floorOf[rpid]! * 60);
    }
    await _settle(r);
    expect(area.calls, 4);
  });

  test('只在需要时才继续往下走', () async {
    final area = _Area(500, deleted: 0.2, seed: 3);
    final r = _resolver(area);
    final first = area.newest(1).first;
    r.request(first, 1700000000 + area.floorOf[first]! * 60);
    await _settle(r);
    final calls = area.calls;
    expect(r.floorOf(first), area.floorOf[first]);
    await _settle(r);
    expect(area.calls, calls, reason: 'idle until more comments are shown');
  });

  test('走查过程中有新评论发出，楼层号仍然准确', () async {
    final area = _Area(300, deleted: 0.2, seed: 5);
    final shown = area.newest(40);
    final r = ReplyFloorResolver(
      fetch: (cursor, ps) {
        if (area.calls == 1) area.post(); // arrives after the first request
        return area.fetch(cursor, ps);
      },
      minInterval: Duration.zero,
    );
    for (final rpid in shown) {
      r.request(rpid, 1700000000 + area.floorOf[rpid]! * 60);
    }
    await _settle(r);
    for (final rpid in shown) {
      final floor = r.floorOf(rpid);
      if (floor != null) expect(floor, area.floorOf[rpid]);
    }
    expect(shown.where((e) => r.floorOf(e) != null).length, greaterThan(30));
  });

  test('置顶等不在时间序列里的旧评论：走过它的时间后放弃，不会一直往下请求', () async {
    final area = _Area(2000, deleted: 0.1, seed: 9);
    final r = _resolver(area);
    final newest = area.newest(20);
    for (final rpid in newest) {
      r.request(rpid, 1700000000 + area.floorOf[rpid]! * 60);
    }
    // an unknown comment whose time is far newer than anything below
    r.request(42, 1700000000 + area.top * 60 + 10000);
    await _settle(r);
    expect(r.floorOf(42), isNull);
    expect(area.calls, lessThan(20));
  });

  test('请求失败后停止，不会反复重试', () async {
    final area = _Area(200)..fail = true;
    final r = _resolver(area);
    for (final rpid in area.newest(20)) {
      r.request(rpid, 0);
    }
    await _settle(r);
    expect(area.calls, 1);
  });
}
