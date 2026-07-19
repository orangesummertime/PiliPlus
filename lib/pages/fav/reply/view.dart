import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/fav/reply/controller.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/reply_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/waterfall.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

class FavReplyPage extends StatefulWidget {
  const FavReplyPage({super.key});

  @override
  State<FavReplyPage> createState() => _FavReplyPageState();
}

class _FavReplyPageState extends State<FavReplyPage>
    with AutomaticKeepAliveClientMixin, DynMixin {
  final FavReplyController _controller = Get.put(FavReplyController());

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return refreshIndicator(
      onRefresh: _controller.onRefresh,
      child: CustomScrollView(
        controller: _controller.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [Obx(() => _buildBody(_controller.loadingState.value))],
      ),
    );
  }

  Widget _buildBody(LoadingState<List<ReplyInfo>?> loadingState) {
    return switch (loadingState) {
      Loading() => const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      ),
      Success(:final response) when response != null && response.isNotEmpty =>
        ViewSliverSafeArea(
          sliver: SliverWaterfallFlow(
            gridDelegate: dynGridDelegate,
            delegate: SliverChildBuilderDelegate(
              childCount: response.length,
              (context, index) {
                if (index == response.length - 1) _controller.onLoadMore();
                final reply = response[index];
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
        ),
      Success() => SliverFillRemaining(
        child: HttpError(onReload: _controller.onReload),
      ),
      Error(:final errMsg) => SliverFillRemaining(
        child: HttpError(errMsg: errMsg, onReload: _controller.onReload),
      ),
    };
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
