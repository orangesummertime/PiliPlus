import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/utils/black_mid_rules.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// Manages online UID rule lists. Returns after the sheet is closed.
Future<void> showBlackMidRuleSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) =>
          _RuleSheet(scrollController: scrollController),
    ),
  );
}

class _RuleSheet extends StatefulWidget {
  const _RuleSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  List<BlackMidRule> _rules = BlackMidRules.load();

  /// urls being updated; empty string means "all"
  final Set<String> _busy = {};

  void _reload() {
    if (mounted) setState(() => _rules = BlackMidRules.load());
  }

  Future<void> _run(String key, Future<String?> Function() action) async {
    if (_busy.isNotEmpty) return;
    setState(() => _busy.add(key));
    try {
      final msg = await action();
      if (msg != null) SmartDialog.showToast(msg);
    } catch (e) {
      SmartDialog.showToast('$e');
    } finally {
      _busy.remove(key);
      _reload();
    }
  }

  Future<void> _showAddDialog() async {
    var text = '';
    final confirm = await showConfirmDialog(
      context: context,
      title: const Text('添加 UID 规则'),
      content: TextField(
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        keyboardType: .url,
        onChanged: (value) => text = value,
        decoration: const InputDecoration(
          hintText: 'https://example.com/uid.txt\n每行一个链接，可一次添加多个',
          border: OutlineInputBorder(),
        ),
      ),
    );
    if (confirm) {
      _run('', () => BlackMidRules.addAndUpdate(text.split(RegExp(r'\s+'))));
    }
  }

  void _showRuleMenu(BlackMidRule rule) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        clipBehavior: .hardEdge,
        contentPadding: const .symmetric(vertical: 12),
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.refresh, size: 20),
            title: const Text('立即更新'),
            onTap: () {
              Get.back();
              _run(rule.url, () => BlackMidRules.update([rule.url]));
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.copy, size: 20),
            title: const Text('复制链接'),
            onTap: () {
              Get.back();
              Utils.copyText(rule.url);
            },
          ),
          ListTile(
            dense: true,
            leading: Icon(
              Icons.delete_outline,
              size: 20,
              color: ColorScheme.of(context).error,
            ),
            title: Text(
              '删除规则',
              style: TextStyle(color: ColorScheme.of(context).error),
            ),
            onTap: () async {
              Get.back();
              final confirm = await showConfirmDialog(
                context: this.context,
                title: const Text('删除该规则？'),
                content: Text(
                  '将移除它添加的 ${rule.owned.length} 个 UID'
                  '（其他规则或手动添加的不受影响）',
                ),
              );
              if (confirm) {
                _run(rule.url, () async {
                  await BlackMidRules.remove(rule.url);
                  return '已删除';
                });
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final outline = TextStyle(fontSize: 12, color: colorScheme.outline);
    final busy = _busy.isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const .fromLTRB(20, 12, 8, 4),
          child: Row(
            children: [
              Text('在线 UID 规则', style: TextTheme.of(context).titleMedium),
              const Spacer(),
              if (busy)
                const Padding(
                  padding: .all(12),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                IconButton(
                  tooltip: '全部更新',
                  onPressed: _rules.isEmpty
                      ? null
                      : () => _run('', BlackMidRules.update),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: '添加',
                  onPressed: _showAddDialog,
                  icon: const Icon(Icons.add),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const .fromLTRB(20, 0, 20, 8),
          child: Text(
            'txt 文件，每行一个或多个 UID（空格/逗号分隔），'
            '支持 space.bilibili.com 链接，# 开头为注释。'
            '每天启动时自动更新。',
            style: outline,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _rules.isEmpty
              ? Center(child: Text('还没有规则，点右上角 + 添加', style: outline))
              : ListView.builder(
                  controller: widget.scrollController,
                  itemCount: _rules.length,
                  itemBuilder: (context, index) {
                    final rule = _rules[index];
                    final updating =
                        _busy.contains(rule.url) || _busy.contains('');
                    final updatedAt = rule.updatedAt;
                    return ListTile(
                      dense: true,
                      onTap: busy ? null : () => _showRuleMenu(rule),
                      title: Text(
                        rule.url,
                        maxLines: 2,
                        overflow: .ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        [
                          '${rule.mids.length} 个 UID，'
                              '新增 ${rule.owned.length}',
                          updatedAt == null
                              ? '未更新'
                              : '更新于 ${DateFormatUtils.format(
                                  updatedAt ~/ 1000,
                                  format: DateFormatUtils.longFormatDs,
                                )}',
                          if (rule.error case final error?) '失败：$error',
                        ].join(' · '),
                        maxLines: 3,
                        overflow: .ellipsis,
                        style: rule.error == null
                            ? outline
                            : outline.copyWith(color: colorScheme.error),
                      ),
                      trailing: updating
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.more_vert, size: 20),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
