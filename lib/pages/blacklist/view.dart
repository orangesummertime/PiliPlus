import 'package:PiliPlus/common/skeleton/msg_feed_top.dart';
import 'package:PiliPlus/common/sliver_single_child_delegate.dart';
import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/dialog/export_import.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/models/common/image_type.dart';
import 'package:PiliPlus/models_new/blacklist/list.dart';
import 'package:PiliPlus/pages/blacklist/controller.dart';
import 'package:PiliPlus/pages/blacklist/rule_sheet.dart';
import 'package:PiliPlus/utils/black_mid_reasons.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

enum _BlockType implements EnumWithLabel {
  local('本地'),
  online('在线'),
  ;

  @override
  final String label;

  _BlockType(this.label);
}

class BlackListPage extends StatefulWidget {
  const BlackListPage({super.key});

  @override
  State<BlackListPage> createState() => _BlackListPageState();
}

class _BlackListPageState extends State<BlackListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _blackListController = Get.put(BlackListController());
  late EdgeInsets padding;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _BlockType.values.length,
      vsync: this,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    padding = MediaQuery.viewPaddingOf(context);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(title: const Text('黑名单管理')),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: _BlockType.values.map((e) => Tab(text: e.label)).toList(),
          ),
          Expanded(
            child: tabBarView(
              controller: _tabController,
              children: _BlockType.values
                  .map(
                    (e) => switch (e) {
                      _BlockType.local => _local,
                      _BlockType.online => _online,
                    },
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget get _online {
    return refreshIndicator(
      onRefresh: _blackListController.onRefresh,
      child: CustomScrollView(
        key: const PageStorageKey(_BlockType.online),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          ViewSliverSafeArea(
            sliver: Obx(
              () => _buildBody(_blackListController.loadingState.value),
            ),
          ),
        ],
      ),
    );
  }

  void _onAddMid(String mid, String reason) {
    if (mid.isEmpty) return;
    int intMid;
    try {
      intMid = int.parse(mid);
    } catch (e) {
      SmartDialog.showToast(e.toString());
      return;
    }
    _blackListController.blackMids.add(intMid);
    BlackMidReasons.setLocal(intMid, reason);
    SmartDialog.showToast('屏蔽成功');
    setState(() {});
  }

  void _showAddMidDialog() {
    var text = '';
    var reason = '';
    showConfirmDialog(
      context: context,
      title: const Text('屏蔽用户'),
      content: Column(
        mainAxisSize: .min,
        spacing: 16,
        children: [
          TextField(
            autofocus: true,
            textInputAction: .next,
            keyboardType: .number,
            onChanged: (value) => text = value,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'UID',
              border: OutlineInputBorder(),
            ),
          ),
          TextField(
            textInputAction: .done,
            onChanged: (value) => reason = value,
            onSubmitted: (_) {
              Get.back();
              _onAddMid(text, reason);
            },
            decoration: const InputDecoration(
              labelText: '原因（可选）',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      onConfirm: () => _onAddMid(text, reason),
    );
  }

  void _showImportExportDialog() {
    showImportExportDialog<List>(
      context,
      title: '黑名单',
      localFileName: () => 'blackMids',
      onExport: () =>
          Utils.jsonEncoder.convert(_blackListController.blackMids.toList()),
      onImport: (json) {
        final mids = Set<int>.from(json);
        _blackListController.blackMids.addAll(mids);
        setState(() {});
      },
    );
  }

  Widget get _local {
    return ScaffoldLayout(
      fab: Padding(
        padding: .only(
          right: kFloatingActionButtonMargin + padding.right,
          bottom: kFloatingActionButtonMargin + padding.bottom,
        ),
        child: Column(
          spacing: kFloatingActionButtonMargin,
          mainAxisSize: .min,
          children: [
            FloatingActionButton(
              tooltip: '在线 UID 规则',
              onPressed: () async {
                await showBlackMidRuleSheet(context);
                if (mounted) setState(() {});
              },
              child: const Icon(Icons.cloud_sync_outlined),
            ),
            FloatingActionButton(
              tooltip: '导入/导出',
              onPressed: _showImportExportDialog,
              child: const Icon(Icons.swap_vert, size: 26),
            ),
            FloatingActionButton(
              tooltip: '添加',
              onPressed: _showAddMidDialog,
              child: const Icon(Icons.add),
            ),
          ],
        ),
      ),
      body: CustomScrollView(
        key: const PageStorageKey(_BlockType.local),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          ViewSliverSafeArea(
            bottom: 180,
            sliver: _buildLocalList(),
          ),
        ],
      ),
    );
  }

  /// Newest first. A snapshot list, so rows are looked up by index in O(1)
  /// (`Set.elementAt` walks the set).
  Widget _buildLocalList() {
    final mids = _blackListController.blackMids.toList(growable: false);
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outline;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const .fromLTRB(16, 12, 16, 4),
            child: Text(
              '共 ${mids.length} 个 · 最近添加的在前',
              style: TextStyle(fontSize: 13, color: outline),
            ),
          ),
        ),
        SliverFixedExtentList.builder(
          itemExtent: 56,
          itemCount: mids.length,
          itemBuilder: (context, index) {
            final mid = mids[mids.length - 1 - index];
            final reason = BlackMidReasons.of(mid);
            return InkWell(
              onTap: () => Get.toNamed('/member?mid=$mid'),
              onLongPress: () => _showLocalMidDialog(mid),
              child: Padding(
                padding: const .symmetric(horizontal: 16),
                child: Row(
                  spacing: 12,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: .center,
                        crossAxisAlignment: .start,
                        children: [
                          Text(
                            mid.toString(),
                            maxLines: 1,
                            style: const TextStyle(fontSize: 15),
                          ),
                          if (reason != null)
                            Text(
                              reason.reason,
                              maxLines: 1,
                              overflow: .ellipsis,
                              style: TextStyle(fontSize: 13, color: outline),
                            ),
                        ],
                      ),
                    ),
                    if (reason?.url != null)
                      Text(
                        '规则',
                        style: TextStyle(fontSize: 12, color: outline),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _showLocalMidDialog(int mid) {
    final reason = BlackMidReasons.of(mid);
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$mid'),
        content: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          spacing: 8,
          children: [
            if (reason == null)
              Text('未填写原因', style: TextStyle(color: theme.colorScheme.outline))
            else ...[
              SelectableText('原因：${reason.reason}'),
              Text(
                reason.url == null ? '来源：本地添加' : '来源：在线规则 ${reason.url}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
              _showEditReasonDialog(mid);
            },
            child: Text(BlackMidReasons.local(mid) == null ? '写原因' : '改原因'),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              _blackListController.blackMids.remove(mid);
              BlackMidReasons.setLocal(mid, null);
              setState(() {});
            },
            child: Text(
              '移除',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
          TextButton(
            onPressed: Get.back,
            child: Text(
              '取消',
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditReasonDialog(int mid) {
    var reason = BlackMidReasons.local(mid) ?? '';
    void save() {
      BlackMidReasons.setLocal(mid, reason);
      setState(() {});
    }

    showConfirmDialog(
      context: context,
      title: Text('$mid 的拉黑原因'),
      content: TextFormField(
        autofocus: true,
        initialValue: reason,
        textInputAction: .done,
        onChanged: (value) => reason = value,
        onFieldSubmitted: (_) {
          Get.back();
          save();
        },
        decoration: const InputDecoration(
          hintText: '留空则清除（规则里的原因不受影响）',
          border: OutlineInputBorder(),
        ),
      ),
      onConfirm: save,
    );
  }

  Widget _buildBody(LoadingState<List<BlackListItem>?> loadingState) {
    late final style = TextStyle(color: Theme.of(context).colorScheme.outline);
    return switch (loadingState) {
      Loading() => const SliverPrototypeExtentList(
        prototypeItem: MsgFeedTopSkeleton(),
        delegate: SliverSingleChildDelegate(
          count: 12,
          child: MsgFeedTopSkeleton(),
        ),
      ),
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverList.builder(
                itemCount: response.length,
                itemBuilder: (BuildContext context, int index) {
                  if (index == response.length - 1) {
                    _blackListController.onLoadMore();
                  }
                  final item = response[index];
                  return ListTile(
                    visualDensity: .standard,
                    onTap: () => Get.toNamed('/member?mid=${item.mid}'),
                    leading: NetworkImgLayer(
                      width: 45,
                      height: 45,
                      type: ImageType.avatar,
                      src: item.face,
                    ),
                    title: Text(
                      item.uname!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      '添加时间: ${DateFormatUtils.format(item.mtime, format: DateFormatUtils.longFormatDs)}',
                      maxLines: 1,
                      style: style,
                      overflow: TextOverflow.ellipsis,
                    ),
                    dense: true,
                    trailing: TextButton(
                      onPressed: () async {
                        final removed = await _blackListController.onRemove(
                          context,
                          index,
                          item.uname,
                          item.mid,
                        );
                        if (mounted && removed) {
                          if (item.mid case final mid?) {
                            BlackMidReasons.setLocal(mid, null);
                          }
                          if (_blackListController.blackMids.remove(item.mid)) {
                            setState(() {});
                          }
                        }
                      },
                      child: const Text('移除'),
                    ),
                  );
                },
              )
            : HttpError(onReload: _blackListController.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _blackListController.onReload,
      ),
    };
  }
}
