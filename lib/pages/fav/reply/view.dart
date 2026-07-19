import 'dart:typed_data';

import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/reply_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/waterfall.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

class FavReplyPage extends StatefulWidget {
  const FavReplyPage({super.key});

  @override
  State<FavReplyPage> createState() => _FavReplyPageState();
}

class _FavReplyPageState extends State<FavReplyPage>
    with AutomaticKeepAliveClientMixin, DynMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder<Box<Uint8List>>(
      valueListenable: GStorage.favReply.listenable(),
      builder: (context, box, _) {
        final replies = box.values.map(ReplyInfo.fromBuffer).toList()
          ..sort((a, b) => b.ctime.compareTo(a.ctime));
        return refreshIndicator(
          onRefresh: () async {},
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              replies.isNotEmpty
                  ? ViewSliverSafeArea(
                      sliver: SliverWaterfallFlow(
                        gridDelegate: dynGridDelegate,
                        delegate: SliverChildBuilderDelegate(
                          childCount: replies.length,
                          (context, index) {
                            final reply = replies[index];
                            return ReplyItemGrpc(
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
                  : const SliverFillRemaining(child: HttpError()),
            ],
          ),
        );
      },
    );
  }

  void _replyReply(ReplyInfo replyInfo, int? rpid) {
    switch (replyInfo.type.toInt()) {
      case 1:
        PiliScheme.videoPush(replyInfo.oid.toInt(), null);
      case 12:
        PageUtils.toDupNamed(
          '/articlePage',
          parameters: {'id': replyInfo.oid.toString(), 'type': 'read'},
        );
      default:
        PageUtils.pushDynFromId(
          rid: replyInfo.oid.toString(),
          type: replyInfo.type,
        );
    }
  }

  void _onCheckReply(ReplyInfo replyInfo) {
    final oid = replyInfo.oid.toInt();
    ReplyUtils.onCheckReply(
      replyInfo: replyInfo,
      biliSendCommAntifraud: Pref.biliSendCommAntifraud,
      sourceId: switch (oid) {
        1 => IdUtils.av2bv(oid),
        _ => oid.toString(),
      },
      isManual: true,
    );
  }
}
