# 海外加速与 PCDN 屏蔽

设置 → 音视频设置，「屏蔽 PCDN/P2P 节点」与「海外加速」两组；播放页「更多」里有「海外加速」快捷面板。

## 海外加速（两个引擎，二选一）

视频经本地回环代理（127.0.0.1）切成小块，多条连接、多个 CDN 节点并发下载，
按顺序交给播放器（mpv）。直播、离线播放不走代理；有数字版权保护或只能试看的剧集不加速。

| 引擎 | 来源 | 本仓库位置 |
| --- | --- | --- |
| 线程撕裂者（默认） | [lemonteaau/PiliPlus](https://github.com/lemonteaau/PiliPlus)（PiliPlus 海外加速版，GPL-3.0），提交 `7432a214` | `lib/services/thread_ripper/`，接入在 `lib/plugin/pl_player/controller.dart`、`lib/pages/video/controller.dart`；原文档 [thread-ripper.md](thread-ripper.md) |
| BTR | [nishuodedui1145-del/PiliPlus](https://github.com/nishuodedui1145-del/PiliPlus)（PiliPlus-BTR，GPL-3.0），提交 `97663e3a` | `lib/services/btr_proxy/`、`lib/pages/setting/widgets/btr_log_page.dart`，接入在 `lib/pages/video/controller.dart`；原文档 [btr/DESIGN.md](btr/DESIGN.md)、[btr/NOTICE-PiliPlus-BTR.md](btr/NOTICE-PiliPlus-BTR.md) |

两者的原理都来自 [MrTangLuyao/Bilibili-thread-ripper](https://github.com/MrTangLuyao/Bilibili-thread-ripper)（MIT，许可见 `assets/licenses/bilibili-thread-ripper.txt`）。

本仓库在移植时的改动：

- 一个总开关加引擎选择（`Pref.overseasAccel`、`Pref.overseasAccelEngine`），两套引擎各自的设置保留；
  默认开启、默认引擎为线程撕裂者、默认大陆节点（与 lemonteaau 版一致）。
- 播放页快捷面板（来自 PiliPlus-BTR 的 `btr_quick_setting.dart`）改为同时管两个引擎：`accel_quick_setting.dart`。
- 两个引擎都不再使用 PCDN 证书的 `upos-sz-mirror14b` 等 P2P 节点（见下）。
- PiliPlus-BTR 原本会把登录 Cookie 发给 CDN 节点；地址本身已签名，普通播放器也不发，这里去掉了。
- 未移植：两个 fork 各自的更新器、Android 启动流程调整、发布用 CI 与 README。

## 屏蔽 PCDN/P2P 节点（默认开）

`VideoUtils.isP2pHost`：节点名单来自 [SukkaW/Make-Bilibili-Great-Than-Ever-Before](https://github.com/SukkaW/Make-Bilibili-Great-Than-Ever-Before)
（MIT，`src/core/player/cdn-classify.ts`，许可见 `assets/licenses/make-bilibili-great-than-ever-before.txt`），
以及 [@gxgexiao 的 Surge 规则](https://x.com/gxgexiao/status/2119003466085646646)（`*pcdn*.biliapi.net`、`mcdn.bilivideo.cn/com`、`szbdyd.com`、`mountaintoys.cn`）。

- 点播：P2P 镜像（`os=mcdn`、`*302*`、`mirror14b` 等）不直接使用，换成官方镜像（签名不变）；
  只能在原节点使用的 `/v1/resource` 地址走 B 站官方代理；「基础URL」模式下首个地址是 P2P 时也不直接用。
- 直播：默认线路是 PCDN（`*.mcdn.bilivideo.*`、`smtcdns` 等）时换成第一个官方线路；手动选的线路保留。

测试：`test/utils/p2p_cdn_test.dart`、`test/thread_ripper_test.dart`、`test/thread_ripper_auto_test.dart`、
`test/video_utils_test.dart`（来自 lemonteaau 版）、`test/btr/`（来自 PiliPlus-BTR，`btr_cdn_racer_test` 第 4 项依赖机器速度，在原仓库同样不过）。
