import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/utils/black_mid_reasons.dart';
import 'package:PiliPlus/utils/black_mid_rules.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// The 已拉黑 badge. When the UID is blocked locally or by an online rule,
/// it is followed by an icon that shows why and lets you whitelist it.
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
    // blocked on the account only (server side): nothing to explain here
    if (!GlobalData().isBlackMid(mid)) return _badge;
    return GestureDetector(
      behavior: .opaque,
      onTap: () => showBlackMidInfo(context, mid),
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

/// Why [mid] is blocked (reason and source), with a button to whitelist it.
void showBlackMidInfo(BuildContext context, int mid) {
  final theme = Theme.of(context);
  final info = BlackMidReasons.of(mid);
  final url = info == null
      ? (GlobalData().blackMids.contains(mid)
            ? null
            : BlackMidRules.sourceOf(mid))
      : info.url;
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('拉黑原因'),
      content: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: 12,
        children: [
          if (info == null)
            Text(
              '没有填写原因',
              style: TextStyle(color: theme.colorScheme.outline),
            )
          else
            SelectableText(info.reason, style: theme.textTheme.bodyLarge),
          Text(
            url == null ? '来源：本地黑名单' : '来源：在线规则 $url',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
      actions: [
        if (info != null)
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: info.reason));
              SmartDialog.showToast('已复制');
            },
            child: const Text('复制'),
          ),
        TextButton(
          onPressed: () {
            Get.back();
            Pref.setWhiteMid(mid);
            SmartDialog.showToast('已加入白名单，刷新后生效');
          },
          child: const Text('加入白名单'),
        ),
        TextButton(onPressed: Get.back, child: const Text('确定')),
      ],
    ),
  );
}
