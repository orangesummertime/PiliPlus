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
            SmartDialog.showToast('已加入白名单');
          },
          child: const Text('加入白名单'),
        ),
        TextButton(onPressed: Get.back, child: const Text('确定')),
      ],
    ),
  );
}

/// Where a user stands in the local lists, for profile cards.
enum MidListStatus { white, black }

/// Black / white list status of [mid]: null when the user is on neither.
({MidListStatus status, bool local, bool rule})? midListStatus(int mid) {
  final data = GlobalData();
  final local = data.blackMids.contains(mid);
  final rule = BlackMidRules.contains(mid);
  if (data.whiteMids.contains(mid)) {
    return (status: MidListStatus.white, local: local, rule: rule);
  }
  if (local || rule) {
    return (status: MidListStatus.black, local: local, rule: rule);
  }
  return null;
}

/// A pill for profile cards: 本地黑名单 / 云端黑名单 / 白名单, with an icon
/// telling them apart. Tap for the reason and to (un)whitelist. Updates in
/// place when the lists change.
class MidListStatusPill extends StatelessWidget {
  const MidListStatusPill({super.key, required this.mid});

  final int mid;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: GlobalData().midListsRevision,
    builder: (context, _, _) {
      final info = midListStatus(mid);
      if (info == null) return const SizedBox.shrink();
      final colorScheme = ColorScheme.of(context);
      final dark = colorScheme.brightness == Brightness.dark;
      final (
        IconData icon,
        String text,
        Color fg,
        Color bg,
      ) = switch (info.status) {
        MidListStatus.white => (
          Icons.verified_user_rounded,
          info.local || info.rule ? '白名单 · 已豁免' : '白名单',
          dark ? const Color(0xFF81C995) : const Color(0xFF1E8E3E),
          (dark ? const Color(0xFF81C995) : const Color(0xFF1E8E3E)).withValues(
            alpha: 0.14,
          ),
        ),
        MidListStatus.black => (
          info.local ? Icons.block_rounded : Icons.cloud_off_rounded,
          info.local && info.rule
              ? '本地 · 云端黑名单'
              : info.local
              ? '本地黑名单'
              : '云端黑名单',
          colorScheme.error,
          colorScheme.error.withValues(alpha: 0.12),
        ),
      };
      return Semantics(
        button: true,
        label: text,
        child: GestureDetector(
          behavior: .opaque,
          onTap: () => info.status == MidListStatus.white
              ? showWhiteMidInfo(context, mid)
              : showBlackMidInfo(context, mid),
          child: Container(
            height: 18,
            padding: const .only(left: 5, right: 7),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: const .all(.circular(9)),
              border: Border.all(color: fg.withValues(alpha: 0.35), width: 0.6),
            ),
            child: Row(
              mainAxisSize: .min,
              spacing: 3,
              children: [
                Icon(icon, size: 12, color: fg),
                Text(
                  text,
                  strutStyle: const StrutStyle(
                    height: 1,
                    leading: 0,
                    fontSize: 10,
                    fontWeight: .bold,
                  ),
                  style: TextStyle(
                    height: 1,
                    fontSize: 10,
                    fontWeight: .bold,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The whitelist entry of [mid]: what it overrides, with a button to remove.
void showWhiteMidInfo(BuildContext context, int mid) {
  final theme = Theme.of(context);
  final info = midListStatus(mid);
  final overrides = [
    if (info?.local ?? false) '本地黑名单',
    if (info?.rule ?? false) '在线规则 ${BlackMidRules.sourceOf(mid)}',
  ];
  final reason = BlackMidReasons.of(mid);
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('白名单'),
      content: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: 12,
        children: [
          Text(
            overrides.isEmpty
                ? '已加入白名单：不会被本地黑名单或在线规则屏蔽。'
                : '已加入白名单，以下屏蔽对 TA 不生效：',
          ),
          for (final o in overrides)
            Text(
              '· $o',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          if (reason != null)
            Text(
              '拉黑原因：${reason.reason}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Get.back();
            Pref.removeWhiteMid(mid);
            SmartDialog.showToast('已移出白名单');
          },
          child: Text(
            '移出白名单',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
        TextButton(onPressed: Get.back, child: const Text('确定')),
      ],
    ),
  );
}
