import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/pages/common/reply_controller.dart';
import 'package:material_ui/material_ui.dart';

/// Leading items of the top level comment list in the classic (经典) layout:
/// the pinned reply, a few hot replies with a "更多热门评论" button, then the
/// header of the replies sorted by time, which the list itself continues.
///
/// Reads the controller's reactive state, so call it inside the `Obx` that
/// builds the list. Returns nothing outside the classic layout.
List<Widget> buildClassicReplyHead({
  required ReplyController controller,
  required ColorScheme colorScheme,
  required Widget Function(ReplyInfo item) buildItem,
}) {
  if (!controller.isClassic) return const [];

  final upTop = controller.classicUpTop.value;
  final hot = controller.classicHot.toList();
  final expanded = controller.classicHotExpanded.value;
  final loading = controller.classicHotLoading.value;
  final limit = controller.classicHotCount;
  final shown = expanded ? hot : hot.take(limit);

  final canExpand =
      !expanded && (hot.length > limit || !controller.classicHotEnd);
  final canLoadMore = expanded && !controller.classicHotEnd;

  return [
    if (upTop != null) buildItem(upTop),
    if (hot.isNotEmpty) ...[
      _SectionTitle(title: '热门评论', colorScheme: colorScheme),
      ...shown.map(buildItem),
      if (canExpand || canLoadMore || expanded)
        _MoreButtons(
          colorScheme: colorScheme,
          moreLabel: loading
              ? '加载中...'
              : canExpand
              ? '更多热门评论'
              : canLoadMore
              ? '加载更多热门评论'
              : null,
          onMore: loading ? null : controller.onClassicHotMore,
          onCollapse: expanded && hot.length > limit
              ? controller.onClassicHotCollapse
              : null,
        ),
    ],
    _SectionTitle(title: '最新评论', colorScheme: colorScheme),
  ];
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.colorScheme});

  final String title;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .fromLTRB(12, 12, 12, 4),
      child: Row(
        spacing: 6,
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: const .all(.circular(2)),
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreButtons extends StatelessWidget {
  const _MoreButtons({
    required this.colorScheme,
    required this.moreLabel,
    required this.onMore,
    required this.onCollapse,
  });

  final ColorScheme colorScheme;
  final String? moreLabel;
  final VoidCallback? onMore;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 13, color: colorScheme.primary);
    return Padding(
      padding: const .only(bottom: 4),
      child: Row(
        mainAxisAlignment: .center,
        children: [
          if (moreLabel case final label?)
            TextButton.icon(
              onPressed: onMore,
              icon: Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: colorScheme.primary,
              ),
              label: Text(label, style: style),
            ),
          if (onCollapse != null)
            TextButton.icon(
              onPressed: onCollapse,
              icon: Icon(
                Icons.keyboard_arrow_up,
                size: 18,
                color: colorScheme.primary,
              ),
              label: Text('收起', style: style),
            ),
        ],
      ),
    );
  }
}
