import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/http/reply.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';

class ZanButtonGrpc extends StatelessWidget {
  const ZanButtonGrpc({
    super.key,
    required this.replyItem,
    this.onBlockedChanged,
  });

  final ReplyInfo replyItem;
  final VoidCallback? onBlockedChanged;

  Future<void> onHateReply(
    BuildContext context, {
    required bool isLike,
    required bool isDislike,
  }) async {
    feedBack();
    final int oid = replyItem.oid.toInt();
    final int rpid = replyItem.id.toInt();
    final int action = isDislike ? 0 : 1;
    final res = await ReplyHttp.hateReply(
      type: replyItem.type.toInt(),
      action: action,
      oid: oid,
      rpid: rpid,
    );
    // SmartDialog.dismiss();
    if (res.isSuccess) {
      SmartDialog.showToast(isDislike ? '取消踩' : '点踩成功');
      if (isDislike) {
        replyItem.replyControl.action = $fixnum.Int64.ZERO;
      } else {
        if (isLike) replyItem.like -= $fixnum.Int64.ONE;
        replyItem.replyControl.action = $fixnum.Int64.TWO;
      }
      if (context.mounted) {
        (context as Element).markNeedsBuild();
      }
    } else {
      res.toast();
    }
  }

  // 评论点赞
  Future<void> onLikeReply(
    BuildContext context, {
    required bool isLike,
    required bool isDislike,
  }) async {
    feedBack();
    final int oid = replyItem.oid.toInt();
    final int rpid = replyItem.id.toInt();
    // 1 已点赞 2 不喜欢 0 未操作
    final int action = isLike ? 0 : 1;
    final res = await ReplyHttp.likeReply(
      type: replyItem.type.toInt(),
      oid: oid,
      rpid: rpid,
      action: action,
    );
    if (res.isSuccess) {
      SmartDialog.showToast(isLike ? '取消赞' : '点赞成功');
      if (isLike) {
        replyItem
          ..like -= $fixnum.Int64.ONE
          ..replyControl.action = $fixnum.Int64.ZERO;
      } else {
        replyItem
          ..like += $fixnum.Int64.ONE
          ..replyControl.action = $fixnum.Int64.ONE;
      }
      if (context.mounted) {
        (context as Element).markNeedsBuild();
      }
    } else {
      res.toast();
    }
  }

  static void _toastNotLogin() {
    SmartDialog.showToast('账号未登录');
  }

  /// mids with a block/unblock request in flight, to ignore repeated taps
  static final Set<int> _pendingBlockMids = {};

  Future<void> onToggleBlock(BuildContext context) async {
    final mid = replyItem.mid.toInt();
    if (!_pendingBlockMids.add(mid)) {
      return;
    }
    try {
      feedBack();
      final isBlocked =
          replyItem.replyControl.blocked ||
          GlobalData().blackMids.contains(mid);
      final res = await VideoHttp.relationMod(
        mid: mid,
        act: isBlocked ? 6 : 5,
        reSrc: 11,
      );
      if (res.isSuccess) {
        replyItem.replyControl.blocked = !isBlocked;
        // keep the local blacklist in sync, otherwise the badge stays after
        // unblocking (it is also read from GlobalData().blackMids)
        if (isBlocked) {
          Pref.removeBlackMid(mid);
        } else {
          Pref.setBlackMid(mid);
        }
        SmartDialog.showToast(isBlocked ? '已取消拉黑' : '已拉黑');
        onBlockedChanged?.call();
        if (context.mounted) {
          (context as Element).markNeedsBuild();
        }
      } else {
        res.toast();
      }
    } finally {
      _pendingBlockMids.remove(mid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLogin = Accounts.main.isLogin;
    final ThemeData theme = Theme.of(context);
    late bool isProcessing = false;
    final action = replyItem.replyControl.action;
    final isLike = action == $fixnum.Int64.ONE;
    final isDislike = action == $fixnum.Int64.TWO;
    final isBlocked =
        replyItem.replyControl.blocked ||
        GlobalData().blackMids.contains(replyItem.mid.toInt());
    final outline = theme.colorScheme.outline;
    final primary = theme.colorScheme.primary;
    final ButtonStyle style = TextButton.styleFrom(
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );

    @pragma('vm:prefer-inline')
    Future<void> wrapProcessing(
      Future<void> Function(
        BuildContext context, {
        required bool isLike,
        required bool isDislike,
      })
      onLikeOrDislike,
    ) async {
      if (isProcessing) return;
      isProcessing = true;
      await onLikeOrDislike(context, isLike: isLike, isDislike: isDislike);
      isProcessing = false;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 32,
          child: TextButton(
            style: const ButtonStyle(
              visualDensity: .compact,
              tapTargetSize: .shrinkWrap,
              padding: WidgetStatePropertyAll(.zero),
              minimumSize: WidgetStatePropertyAll(.square(40)),
            ),
            onPressed: isLogin
                ? () => wrapProcessing(onHateReply)
                : _toastNotLogin,
            child: Icon(
              isDislike
                  ? FontAwesomeIcons.solidThumbsDown
                  : FontAwesomeIcons.thumbsDown,
              size: 16,
              color: isDislike ? primary : outline,
              semanticLabel: isDislike ? '已踩' : '点踩',
            ),
          ),
        ),
        SizedBox(
          height: 32,
          child: TextButton(
            style: const ButtonStyle(
              visualDensity: .compact,
              tapTargetSize: .shrinkWrap,
              padding: WidgetStatePropertyAll(.zero),
              minimumSize: WidgetStatePropertyAll(.square(40)),
            ),
            onPressed: () => onToggleBlock(context),
            child: Icon(
              isBlocked ? Icons.block : Icons.block_outlined,
              size: 17,
              color: isBlocked ? primary : outline,
              semanticLabel: isBlocked ? '已拉黑' : '拉黑',
            ),
          ),
        ),
        SizedBox(
          height: 32,
          child: TextButton(
            style: style,
            onPressed: isLogin
                ? () => wrapProcessing(onLikeReply)
                : _toastNotLogin,
            child: Row(
              spacing: 4,
              children: [
                Icon(
                  isLike
                      ? FontAwesomeIcons.solidThumbsUp
                      : FontAwesomeIcons.thumbsUp,
                  size: 16,
                  color: isLike ? primary : outline,
                  semanticLabel: isLike ? '已赞' : '点赞',
                ),
                Text(
                  NumUtils.numFormat(replyItem.like.toInt()),
                  style: TextStyle(
                    color: isLike ? primary : outline,
                    fontSize: theme.textTheme.labelSmall!.fontSize,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
