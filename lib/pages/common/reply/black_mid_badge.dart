import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/utils/black_mid_reasons.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// The 已拉黑 badge; with a known reason, followed by an icon that shows it.
class BlackMidBadge extends StatelessWidget {
  const BlackMidBadge({super.key, required this.mid});

  final int mid;

  static const _badge = PBadge(
    text: '已拉黑',
    size: .small,
    isStack: false,
    fontSize: 9,
  );

  @override
  Widget build(BuildContext context) {
    final info = BlackMidReasons.of(mid);
    if (info == null) return _badge;
    return GestureDetector(
      behavior: .opaque,
      onTap: () => showBlackMidReason(context, info),
      child: Row(
        spacing: 2,
        mainAxisSize: .min,
        children: [
          _badge,
          Icon(
            Icons.info_outline,
            size: 13,
            color: ColorScheme.of(context).outline,
          ),
        ],
      ),
    );
  }
}

void showBlackMidReason(
  BuildContext context,
  ({String reason, String? url}) info,
) {
  final theme = Theme.of(context);
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('拉黑原因'),
      content: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: 12,
        children: [
          SelectableText(info.reason, style: theme.textTheme.bodyLarge),
          Text(
            info.url == null ? '来源：本地添加' : '来源：在线规则 ${info.url}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: info.reason));
            SmartDialog.showToast('已复制');
          },
          child: const Text('复制'),
        ),
        TextButton(onPressed: Get.back, child: const Text('确定')),
      ],
    ),
  );
}
