// Settings of the overseas acceleration engines and PCDN blocking.
//
// The thread-ripper items are from lemonteaau/PiliPlus and the BTR items from
// nishuodedui1145-del/PiliPlus-BTR (both lib/pages/setting/models/
// video_settings.dart, GPL-3.0), regrouped under one switch and an engine
// choice.
import 'package:PiliPlus/models/common/video/overseas_accel_engine.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/widgets/btr_log_page.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/services/btr_proxy/proxy_server.dart';
import 'package:PiliPlus/services/btr_proxy/range_core.dart';
import 'package:PiliPlus/services/thread_ripper/cdn_resolver.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

List<SettingsModel> get overseasAccelSettings => [
  SwitchModel(
    title: '屏蔽 PCDN/P2P 节点',
    subtitle:
        '不使用 mcdn、szbdyd、mountaintoys、302 节点等 PCDN / P2P 地址，'
        '换成官方镜像或官方代理；直播默认线路是 PCDN 时也换成官方线路',
    leading: const Icon(Icons.block_outlined),
    setKey: SettingBoxKey.blockP2pCdn,
    defaultVal: true,
    onChanged: (value) => VideoUtils.blockP2p = value,
  ),
  const SwitchModel(
    title: '海外加速',
    subtitle:
        '视频经本地代理切成小块，多条连接、多个节点并发下载，'
        '缓解海外看 B 站的卡顿和黑屏；直播、离线播放不走代理，下次加载视频生效',
    leading: Icon(Icons.bolt_outlined),
    setKey: SettingBoxKey.overseasAccel,
    defaultVal: true,
  ),
  NormalModel(
    title: '海外加速：引擎',
    leading: const Icon(Icons.settings_input_component_outlined),
    getSubtitle: () =>
        '当前：${Pref.overseasAccelEngine.label}（${Pref.overseasAccelEngine.source}）',
    onTap: (context, setState) async {
      final res = await showDialog<OverseasAccelEngine>(
        context: context,
        builder: (context) => SelectDialog<OverseasAccelEngine>(
          title: '海外加速：引擎',
          value: Pref.overseasAccelEngine,
          values: [
            for (final e in OverseasAccelEngine.values)
              (e, '${e.label}（${e.source}）'),
          ],
        ),
      );
      if (res != null) {
        await GStorage.setting.put(SettingBoxKey.overseasAccelEngine, res.name);
        setState();
      }
    },
  ),
  const SwitchModel(
    title: '海外加速：剧集加速',
    subtitle: '加速番剧、电影、纪录片等剧集；有数字版权保护或只能试看的剧集不加速',
    leading: Icon(Icons.movie_outlined),
    setKey: SettingBoxKey.threadRipperEpisodeEnabled,
    defaultVal: true,
  ),

  // ---- thread-ripper (lemonteaau/PiliPlus) ----
  const SwitchModel(
    title: '线程撕裂者：海外节点',
    subtitle:
        '默认关闭，使用大陆节点（海外观看也推荐，冷门视频不会卡在没有缓存的海外节点上）；'
        '只在连大陆网络很差时开启。自定义节点为空时生效',
    leading: Icon(Icons.public),
    setKey: SettingBoxKey.threadRipperOverseas,
    defaultVal: false,
  ),
  const SwitchModel(
    title: '线程撕裂者：自动并发数（推荐）',
    subtitle: '开播先用 16 线程，再根据卡顿和缓冲在 8–64 线程间调整；关闭时使用手动并发数',
    leading: Icon(Icons.auto_graph),
    setKey: SettingBoxKey.threadRipperAutoConcurrency,
    defaultVal: true,
  ),
  NormalModel(
    title: '线程撕裂者：并发数',
    leading: const Icon(Icons.call_split),
    getSubtitle: () => Pref.threadRipperAutoConcurrency
        ? '自动（手动设为 ${Pref.threadRipperConcurrency}，自动并发数开启时不生效）'
        : '当前 ${Pref.threadRipperConcurrency}，音视频共享连接上限',
    onTap: (context, setState) async {
      final result = await showDialog<int>(
        context: context,
        builder: (context) => SelectDialog<int>(
          title: '线程撕裂者：并发数',
          value: Pref.threadRipperConcurrency,
          values: Pref.threadRipperConcurrencyValues
              .map((e) => (e, '$e'))
              .toList(),
        ),
      );
      if (result != null) {
        await GStorage.setting.put(
          SettingBoxKey.threadRipperConcurrency,
          result,
        );
        if (context.mounted) setState();
      }
    },
  ),
  NormalModel(
    title: '线程撕裂者：自定义节点',
    leading: const Icon(Icons.dns_outlined),
    getSubtitle: () => Pref.threadRipperCustomHosts.isEmpty
        ? '未启用，使用大陆／海外节点'
        : '只使用 ${Pref.threadRipperCustomHosts.length} 个自定义节点',
    onTap: _showRipperCustomHostsDialog,
  ),

  // ---- BTR (nishuodedui1145-del/PiliPlus-BTR) ----
  NormalModel(
    title: 'BTR：并发上限',
    leading: const Icon(Icons.speed_outlined),
    getSubtitle: () =>
        '当前：${Pref.btrConcurrency} 线程。建议 8 起步，不够再试 16/32（32 以上反而可能更慢）；'
        '实际会按实测速度自适应下探；音频流固定 2 条',
    onTap: (context, setState) async {
      final res = await showDialog<int>(
        context: context,
        builder: (context) => SelectDialog<int>(
          title: 'BTR：并发上限',
          value: Pref.btrConcurrency,
          values: const [4, 8, 16, 32, 64].map((e) => (e, '$e 线程')).toList(),
        ),
      );
      if (res != null) {
        await GStorage.setting.put(SettingBoxKey.btrConcurrency, res);
        setState();
      }
    },
  ),
  NormalModel(
    title: 'BTR：节点分组',
    leading: const Icon(Icons.hub_outlined),
    getSubtitle: () => switch (Pref.btrGroup) {
      'mainland' => '当前：固定用大陆节点',
      'overseas' => '当前：固定用海外节点',
      _ => '当前：自动 —— 起播时两组各测一批，选快的一组',
    },
    onTap: (context, setState) async {
      final res = await showDialog<String>(
        context: context,
        builder: (context) => SelectDialog<String>(
          title: 'BTR：节点分组',
          value: Pref.btrGroup,
          values: const [
            ('auto', '自动（起播测速后选快的一组，推荐）'),
            ('mainland', '大陆节点'),
            ('overseas', '海外节点（连大陆网络差时用）'),
          ],
        ),
      );
      if (res != null) {
        await GStorage.setting.put(SettingBoxKey.btrGroup, res);
        setState();
      }
    },
  ),
  SwitchModel(
    title: 'BTR：CDN 自动竞速',
    subtitle: '进入视频时快速竞速候选 CDN 节点，优先选用实测最快节点',
    leading: const Icon(Icons.speed),
    setKey: SettingBoxKey.btrCdnRace,
    defaultVal: true,
    onChanged: (value) {
      BtrProxyServer.instance.cdnRaceEnabled = value;
      if (!value) BtrProxyServer.instance.clearAllRacerHints();
    },
  ),
  NormalModel(
    title: 'BTR：日志',
    leading: const Icon(Icons.article_outlined),
    getSubtitle: () => '查看与导出 BTR 本地运行诊断日志（当前 ${BtrLog.length} 行）',
    onTap: (context, setState) =>
        Get.to(() => const BtrLogPage())?.then((_) => setState()),
  ),
  NormalModel(
    title: '海外加速：致谢',
    leading: const Icon(Icons.favorite_outline),
    getSubtitle: () =>
        '线程撕裂者引擎来自 lemonteaau/PiliPlus，BTR 引擎来自 '
        'nishuodedui1145-del/PiliPlus-BTR，原理来自 MrTangLuyao/Bilibili-thread-ripper；'
        'PCDN 名单来自 SukkaW/Make-Bilibili-Great-Than-Ever-Before',
    onTap: (context, setState) {},
  ),
];

Future<void> _showRipperCustomHostsDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  var input = Pref.threadRipperCustomHosts.join('\n');
  final form = GlobalKey<FormState>();
  List<String> parse(String value) =>
      value.split(RegExp(r'[\s,，]+')).where((s) => s.isNotEmpty).toList();
  final result = await showDialog<List<String>>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('线程撕裂者：自定义节点'),
      content: SingleChildScrollView(
        child: Form(
          key: form,
          child: TextFormField(
            initialValue: input,
            minLines: 3,
            maxLines: 8,
            onChanged: (value) => input = value,
            decoration: const InputDecoration(
              hintText: 'upos-sz-mirroraliov.bilivideo.com',
              helperText: '每行一个 B站媒体节点，最多 32 个。\n清空恢复大陆／海外模式。',
            ),
            validator: (value) {
              final hosts = parse(value ?? '');
              if (hosts.length > 32) return '最多添加 32 个节点';
              if (hosts.any(
                (h) => RipperCdnResolver.normalizeHost(h) == null,
              )) {
                return '请输入有效的 B站媒体服务器地址';
              }
              return null;
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(
                context,
                parse(input)
                    .map(RipperCdnResolver.normalizeHost)
                    .whereType<String>()
                    .toSet()
                    .toList(),
              );
            }
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  if (result != null) {
    await GStorage.setting.put(SettingBoxKey.threadRipperCustomHosts, result);
    setState();
  }
}
