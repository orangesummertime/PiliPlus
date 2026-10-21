import 'dart:async' show StreamSubscription;

import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/pages/video/reply_reply/view.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/bili_utils.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/reply_scheme_helper.dart';
import 'package:PiliPlus/utils/reply_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/waterfall.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

/// Locally saved replies.
///
/// Storage format is unchanged since the first version: box `favReply`,
/// key = reply id as string, value = `ReplyInfo` protobuf bytes.
class FavReplyPage extends StatefulWidget {
  const FavReplyPage({super.key});

  @override
  State<FavReplyPage> createState() => _FavReplyPageState();
}

class _FavReplyPageState extends State<FavReplyPage>
    with AutomaticKeepAliveClientMixin, DynMixin {
  @override
  bool get wantKeepAlive => true;

  /// Decoded once; afterwards only the changed entry is decoded.
  final Map<String, ReplyInfo> _byKey = {};
  List<ReplyInfo> _replies = const [];
  StreamSubscription<BoxEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = GStorage.favReply.watch().listen(_onBoxEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _load() {
    _byKey.clear();
    final box = GStorage.favReply;
    for (final key in box.keys) {
      final value = box.get(key);
      if (value == null) continue;
      try {
        _byKey[key.toString()] = ReplyInfo.fromBuffer(value);
      } catch (_) {
        // skip a corrupted entry instead of breaking the whole page
      }
    }
    _sort();
  }

  void _onBoxEvent(BoxEvent event) {
    final key = event.key.toString();
    if (event.deleted) {
      if (_byKey.remove(key) == null) return;
    } else {
      final value = event.value;
      if (value is! List<int>) return;
      try {
        _byKey[key] = ReplyInfo.fromBuffer(value);
      } catch (_) {
        return;
      }
    }
    _sort();
    if (mounted) setState(() {});
  }

  void _sort() {
    // newest first; rpid is not aligned with time
    _replies = _byKey.values.toList()
      ..sort((a, b) => b.ctime.compareTo(a.ctime));
  }

  Future<void> _onRefresh() async {
    _load();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return refreshIndicator(
      onRefresh: _onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_replies.isNotEmpty)
            ViewSliverSafeArea(
              sliver: SliverMasonryGrid(
                crossAxisSpacing: 4,
                gridDelegate: dynGridDelegate,
                delegate: SliverChildBuilderDelegate(
                  childCount: _replies.length,
                  (context, index) {
                    final reply = _replies[index];
                    return ReplyItemGrpc(
                      key: ValueKey(reply.id),
                      replyLevel: 0,
                      needDivider: false,
                      replyItem: reply,
                      replyReply: _replyReply,
                      onCheckReply: _onCheckReply,
                    );
                  },
                ),
              ),
            )
          else
            const HttpError(errMsg: '还没有收藏评论，可在评论的更多菜单中收藏'),
        ],
      ),
    );
  }

  /// Jump to the reply in its source page (video / article / dynamic),
  /// same routing as the "我的评论" page.
  void _replyReply(ReplyInfo replyInfo, int? rpid) {
    int? rootRpId, secondRpId;
    final id = replyInfo.id.toInt();
    if (replyInfo.hasRoot() && replyInfo.root != 0) {
      rootRpId = replyInfo.root.toInt();
      secondRpId = id;
    } else {
      rootRpId = id;
    }
    final type = replyInfo.type.toInt();
    switch (type) {
      case 1:
        PiliScheme.videoPush(
          replyInfo.oid.toInt(),
          null,
          rootRpId: rootRpId,
          secondRpId: secondRpId,
        );
      case 12:
        PageUtils.toDupNamed(
          '/articlePage',
          parameters: {
            'id': replyInfo.oid.toString(),
            'type': 'read',
          },
          arguments: {
            rootRpIdKey: rootRpId,
            secondRpIdKey: ?secondRpId,
          },
        );
      case _:
        if (BiliUtils.isDynOrArticle(type)) {
          PageUtils.pushDynFromId(
            rid: replyInfo.oid.toString(),
            type: type,
            rootRpId: rootRpId,
            secondRpId: secondRpId,
          );
        } else {
          VideoReplyReplyPanel.toReply(
            oid: replyInfo.oid.toInt(),
            rootId: rootRpId,
            rpId: secondRpId,
            type: type,
          );
        }
    }
  }

  void _onCheckReply(ReplyInfo replyInfo) {
    final oid = replyInfo.oid.toInt();
    ReplyUtils.onCheckReply(
      replyInfo: replyInfo,
      biliSendCommAntifraud: Pref.biliSendCommAntifraud,
      sourceId: switch (replyInfo.type.toInt()) {
        1 => IdUtils.av2bv(oid),
        _ => oid.toString(),
      },
      isManual: true,
    );
  }
}
