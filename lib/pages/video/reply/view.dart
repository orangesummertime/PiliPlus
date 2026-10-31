import 'package:PiliPlus/common/skeleton/video_reply.dart';
import 'package:PiliPlus/common/sliver_single_child_delegate.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/edge_swipe_dismiss.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_floating_header.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/fab_mixin.dart';
import 'package:PiliPlus/pages/common/reply/classic_reply_head.dart';
import 'package:PiliPlus/pages/video/reply/controller.dart';
import 'package:PiliPlus/pages/video/reply/vote/reply_vote_item.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/pages/video/reply_reply/view.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class VideoReplyPanel extends StatefulWidget {
  const VideoReplyPanel({
    super.key,
    this.replyLevel = 1,
    required this.heroTag,
    required this.isNested,
  });

  final int replyLevel;
  final String heroTag;
  final bool isNested;

  @override
  State<VideoReplyPanel> createState() => _VideoReplyPanelState();
}

class _VideoReplyPanelState extends State<VideoReplyPanel>
    with
        AutomaticKeepAliveClientMixin,
        SingleTickerProviderStateMixin,
        BaseFabMixin,
        FabMixin {
  late ColorScheme colorScheme;
  late VideoReplyController _videoReplyController;

  String get heroTag => widget.heroTag;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _videoReplyController = Get.find<VideoReplyController>(tag: heroTag);
    if (_videoReplyController.loadingState.value is Loading) {
      _videoReplyController.queryData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _videoReplyController.didChangeDependencies(context);
    colorScheme = ColorScheme.of(context);
    bottom = MediaQuery.viewPaddingOf(context).bottom;
  }

  late double bottom;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return fabAnimWrapper(
      child: refreshIndicator(
        onRefresh: _videoReplyController.onRefresh,
        isClampingScrollPhysics: widget.isNested,
        child: ScaffoldLayout(
          body: CustomScrollView(
            controller: widget.isNested
                ? null
                : _videoReplyController.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            key: const PageStorageKey(_VideoReplyPanelState),
            slivers: [
              SliverFloatingHeaderWidget(
                backgroundColor: colorScheme.surface,
                child: Padding(
                  padding: const .fromLTRB(12, 2.5, 6, 2.5),
                  child: Obx(() {
                    final sortType = _videoReplyController.sortType.value;
                    return Row(
                      mainAxisAlignment: .spaceBetween,
                      children: [
                        Text(
                          sortType.desc,
                          style: const TextStyle(fontSize: 13),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          style: Style.buttonStyle,
                          onPressed:
                              _videoReplyController.removedReplies.isEmpty
                              ? null
                              : _showRemovedReplies,
                          icon: Icon(
                            Icons.filter_alt_off_outlined,
                            size: 16,
                            color: _videoReplyController.removedReplies.isEmpty
                                ? colorScheme.outline
                                : colorScheme.secondary,
                          ),
                          label: Text(
                            '已过滤 ${_videoReplyController.removedReplies.length}',
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  _videoReplyController.removedReplies.isEmpty
                                  ? colorScheme.outline
                                  : colorScheme.secondary,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          style: Style.buttonStyle,
                          onPressed: _videoReplyController.queryBySort,
                          icon: Icon(
                            Icons.sort,
                            size: 16,
                            color: colorScheme.secondary,
                          ),
                          label: Text(
                            sortType.descShort,
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.secondary,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
              Obx(() => _buildBody(_videoReplyController.loadingState.value)),
            ],
          ),
          fab: SlideTransition(
            position: fabAnimation,
            child: Padding(
              padding: .only(
                right: kFloatingActionButtonMargin,
                bottom: kFloatingActionButtonMargin + bottom,
              ),
              child: FloatingActionButton(
                heroTag: null,
                onPressed: () {
                  feedBack();
                  _videoReplyController.onReply(
                    null,
                    oid: _videoReplyController.aid,
                    replyType: _videoReplyController.videoType.replyType,
                    mentionItem: _videoReplyController.mentionItem,
                  );
                },
                tooltip: '发表评论',
                child: const Icon(Icons.reply),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(LoadingState<List<ReplyInfo>?> loadingState) {
    switch (loadingState) {
      case Loading():
        return const SliverPrototypeExtentList(
          prototypeItem: VideoReplySkeleton(),
          delegate: SliverSingleChildDelegate(
            count: 5,
            child: VideoReplySkeleton(),
          ),
        );
      case Success(:final response):
        if (response != null && response.isNotEmpty) {
          final head = buildClassicReplyHead(
            controller: _videoReplyController,
            colorScheme: colorScheme,
            buildItem: _buildClassicItem,
          );
          // classic: replies shown in the head are left out below
          final indices = _videoReplyController.classicListIndices(response);
          final listLength = indices?.length ?? response.length;
          var count = listLength + 1 + head.length;
          final voteCard = _videoReplyController.voteCard;
          final hasVote = voteCard != null;
          if (hasVote) {
            count++;
          }
          return SliverList.builder(
            itemBuilder: (context, index) {
              if (hasVote) {
                if (index == 0) {
                  return buildVoteCard(context, colorScheme, voteCard);
                } else {
                  index--;
                }
              }
              if (index < head.length) {
                return head[index];
              }
              index -= head.length;
              if (index == listLength) {
                _videoReplyController.onLoadMore();
                return Container(
                  height: 125,
                  alignment: .center,
                  margin: .only(bottom: bottom),
                  child: Text(
                    _videoReplyController.isEnd ? '没有更多了' : '加载中...',
                    textAlign: .center,
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                );
              } else {
                index = indices?[index] ?? index;
                final item = response[index];
                final child = ReplyItemGrpc(
                  replyItem: item,
                  replyLevel: widget.replyLevel,
                  floorResolver: _videoReplyController.floorResolver,
                  floorBySearch: item.replyControl.isUpTop,
                  replyReply: _videoReplyController.replyReply,
                  onReply: _videoReplyController.onReply,
                  onDelete: (item, subIndex) =>
                      _videoReplyController.onRemove(index, item, subIndex),
                  upMid: _videoReplyController.upMid,
                  getTag: () => heroTag,
                  onCheckReply: _videoReplyController.onCheckReply,
                  onToggleTop: (item) => _videoReplyController.onToggleTop(
                    item,
                    index,
                    _videoReplyController.aid,
                    _videoReplyController.videoType.replyType,
                  ),
                );
                if (item.id == _videoReplyController.targetRootRpId) {
                  return _videoReplyController.colorAnimWrapper(
                    colorScheme,
                    child,
                  );
                }
                return child;
              }
            },
            itemCount: count,
          );
        }

        final child = HttpError(
          errMsg: '还没有评论',
          onReload: _videoReplyController.onReload,
        );
        if (_videoReplyController.voteCard case final voteCard?) {
          return SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: buildVoteCard(context, colorScheme, voteCard),
              ),
              child,
            ],
          );
        }
        return child;
      case Error(:final errMsg):
        return HttpError(
          errMsg: errMsg,
          onReload: _videoReplyController.onReload,
        );
    }
  }

  void _showRemovedReplies() {
    showEdgeSwipeModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const .fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Text(
                    '被剔除的评论',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: Get.back,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Obx(
                () => ListView.builder(
                  controller: scrollController,
                  itemCount: _videoReplyController.removedReplies.length,
                  itemBuilder: (context, index) {
                    final reply = _videoReplyController.removedReplies[index];
                    final item = ReplyItemGrpc(
                      replyItem: reply,
                      replyLevel: widget.replyLevel,
                      replyReply: _openRemovedReplyThread,
                      onReply: _videoReplyController.onReply,
                      upMid: _videoReplyController.upMid,
                      getTag: () => heroTag,
                      onCheckReply: (item) => _videoReplyController
                          .onCheckReply(item, isManual: true),
                    );
                    if (!_isSubReply(reply)) return item;
                    // a filtered reply inside a thread: show it nested
                    final outline = Theme.of(context).colorScheme.outline;
                    return Padding(
                      padding: const .only(left: 24),
                      child: Column(
                        crossAxisAlignment: .start,
                        children: [
                          Padding(
                            padding: const .fromLTRB(12, 10, 12, 0),
                            child: Row(
                              spacing: 4,
                              children: [
                                Icon(
                                  Icons.subdirectory_arrow_right,
                                  size: 14,
                                  color: outline,
                                ),
                                Text(
                                  '楼中楼回复',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          item,
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A pinned or hot reply in the classic head.
  Widget _buildClassicItem(ReplyInfo item) => ReplyItemGrpc(
    replyItem: item,
    replyLevel: widget.replyLevel,
    floorResolver: _videoReplyController.floorResolver,
    floorBySearch: true,
    replyReply: _videoReplyController.replyReply,
    onReply: _videoReplyController.onReply,
    onDelete: _videoReplyController.onRemoveClassic,
    upMid: _videoReplyController.upMid,
    getTag: () => heroTag,
    onCheckReply: _videoReplyController.onCheckReply,
    onToggleTop: (item) => _videoReplyController.onToggleTop(
      item,
      -1,
      _videoReplyController.aid,
      _videoReplyController.videoType.replyType,
    ),
  );

  static bool _isSubReply(ReplyInfo reply) =>
      reply.root != 0 && reply.root != reply.id;

  /// Opens the thread of a filtered reply as a page above the sheet; the
  /// in-page thread panel would open underneath the modal sheet.
  void _openRemovedReplyThread(ReplyInfo reply, int? childId) {
    final isSub = _isSubReply(reply);
    VideoReplyReplyPanel.toReply(
      oid: reply.oid.toInt(),
      // a filtered sub reply belongs to its root's thread
      rootId: isSub ? reply.root.toInt() : reply.id.toInt(),
      rpId: isSub ? reply.id.toInt() : childId,
      type: reply.type.toInt(),
    );
  }
}
