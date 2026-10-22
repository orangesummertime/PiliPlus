import 'dart:io';

import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/reply/reply_sort_type.dart';
import 'package:PiliPlus/pages/common/reply_controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

ReplyInfo _reply(int id) => ReplyInfo(id: Int64(id));

MainListReply _page(
  List<int> ids, {
  required int next,
  bool end = false,
  int? upTop,
}) => MainListReply(
  replies: ids.map(_reply),
  cursor: CursorReply(next: Int64(next), isEnd: end),
  upTop: upTop == null ? null : _reply(upTop),
  subjectControl: SubjectControl(count: Int64(100)),
);

/// Serves fake pages: hot ids are 100+, time ids are 1..; cursor = page index.
class _Controller extends ReplyController<MainListReply> {
  final requests = <String>[];

  @override
  dynamic get sourceId => 1;

  @override
  List<ReplyInfo>? getDataList(MainListReply response) => response.replies;

  @override
  Future<LoadingState<MainListReply>> customGetData() async {
    final page = (cursorNext ?? Int64.ZERO).toInt();
    final hot = mode == Mode.MAIN_LIST_HOT;
    requests.add('${hot ? 'hot' : 'time'}:$page');
    final base = (hot ? 100 : 0) + page * 10;
    return Success(
      _page(
        [for (var i = 1; i <= 10; i++) base + i],
        next: page + 1,
        end: hot && page == 1,
        upTop: 999,
      ),
    );
  }
}

List<int> _ids(Iterable<ReplyInfo> list) =>
    list.map((e) => e.id.toInt()).toList();

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('piliplus-classic-');
    Hive.init(dir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  _Controller create(ReplySortType sort) {
    GStorage.setting.put(SettingBoxKey.replySortType, sort.index);
    return _Controller()..onInit();
  }

  test('经典：热评来自最热接口，列表按时间，置顶在头部', () async {
    final c = create(ReplySortType.classic);
    expect(c.isClassic, isTrue);
    await c.queryData();

    expect(c.requests, ['hot:0', 'time:0']);
    expect(_ids(c.classicHot), [for (var i = 101; i <= 110; i++) i]);
    expect(c.classicUpTop.value?.id.toInt(), 999);
    // pinned reply is not duplicated into the by-time list
    expect(_ids(c.loadingState.value.data!), [for (var i = 1; i <= 10; i++) i]);
    expect(c.classicHotCount, 3);
  });

  test('更多热门评论：先展开，再分页加载，不影响按时间的分页', () async {
    final c = create(ReplySortType.classic);
    await c.queryData();

    await c.onClassicHotMore(); // expand only: 10 loaded > 3 shown
    expect(c.classicHotExpanded.value, isTrue);
    expect(c.requests, ['hot:0', 'time:0']);

    await c.onClassicHotMore(); // next hot page
    expect(c.requests.last, 'hot:1');
    expect(c.classicHot.length, 20);
    expect(c.classicHotEnd, isTrue);

    await c.onLoadMore(); // by-time paging continues from its own cursor
    expect(c.requests.last, 'time:1');
    expect(_ids(c.loadingState.value.data!).last, 20);

    c.onClassicHotCollapse();
    expect(c.classicHotExpanded.value, isFalse);
  });

  test('排序切换：最新 → 最热 → 经典 → 最新，离开经典时清空头部', () async {
    final c = create(ReplySortType.time);
    await c.queryData();
    expect(c.requests, ['time:0']);
    expect(
      c.loadingState.value.data!.first.id.toInt(),
      999,
      reason: 'pinned first',
    );

    c.queryBySort();
    expect(c.sortType.value, ReplySortType.hot);
    await Future<void>.delayed(Duration.zero);
    c.queryBySort();
    expect(c.sortType.value, ReplySortType.classic);
    await Future<void>.delayed(Duration.zero);
    await c.queryData();
    expect(c.classicHot, isNotEmpty);

    c.queryBySort();
    expect(c.sortType.value, ReplySortType.time);
    await c.queryData();
    expect(c.classicHot, isEmpty);
    expect(c.classicUpTop.value, isNull);
  });

  test('删除头部评论', () async {
    final c = create(ReplySortType.classic);
    await c.queryData();
    final hot = c.classicHot.first;
    c.onRemoveClassic(hot, null);
    expect(c.classicHot.contains(hot), isFalse);
    c.onRemoveClassic(c.classicUpTop.value!, null);
    expect(c.classicUpTop.value, isNull);
  });
}
