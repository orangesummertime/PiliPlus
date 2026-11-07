import 'package:PiliPlus/models/common/video/cdn_type.dart';
import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/models_new/live/live_room_play_info/codec.dart';
import 'package:PiliPlus/models_new/live/live_room_play_info/url_info.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:flutter_test/flutter_test.dart';

const _sig = '/upgcxcode/01/02/v.m4s?deadline=1&upsig=abc&os=';

void main() {
  setUp(() {
    VideoUtils.cdnService = CDNService.backupUrl;
    VideoUtils.disableAudioCDN = false;
    VideoUtils.blockP2p = true;
    VideoUtils.liveCdnUrl = null;
  });

  test('P2P / PCDN hosts (Sukka + the Surge rules)', () {
    for (final host in [
      'upos-sz-302ppio.bilivideo.com',
      'upos-sz-302kodo.bilivideo.com',
      'xy1x2x3x4xy.mcdn.bilivideo.cn',
      'abc.mcdn.bilivideo.com',
      'a.szbdyd.com',
      'x.nexusedgeio.com',
      'x.ahdohpiechei.com',
      'x.mountaintoys.cn',
      'x.bvmlt.top',
      'upos-sz-mirror14b.bilivideo.com',
      'upos-xx-pcdn-01.biliapi.net',
      'pcdn.biliapi.net',
      'a.b.smtcdns.net',
    ]) {
      expect(VideoUtils.isP2pHost(host), isTrue, reason: host);
    }
    for (final host in [
      'upos-sz-mirrorali.bilivideo.com',
      'upos-sz-mirrorcos.bilivideo.com',
      'cn-sccd-cu-01-01.bilivideo.com',
      'upos-hz-mirrorakam.akamaized.net',
      'api.biliapi.net',
      'd1--cn-gotcha208.bilivideo.com',
    ]) {
      expect(VideoUtils.isP2pHost(host), isFalse, reason: host);
    }
  });

  test('备用URL：跳过 P2P 镜像，取官方镜像', () {
    expect(
      VideoUtils.getCdnUrl([
        'https://upos-sz-mirror14b.bilivideo.com${_sig}14b',
        'https://upos-sz-mirrorcos.bilivideo.com${_sig}cos',
      ]),
      'https://upos-sz-mirrorcos.bilivideo.com${_sig}cos',
    );
  });

  test('只有 P2P 地址：换到官方镜像（签名不变）', () {
    expect(
      VideoUtils.getCdnUrl([
        'http://upos-sz-302ppio.bilivideo.com:8000${_sig}ppio',
        'https://upos-sz-mirror14b.bilivideo.com${_sig}14b',
      ]),
      'https://${CDNService.ali.host}${_sig}ppio',
    );
  });

  test('基础URL 是 P2P 时不直接用', () {
    VideoUtils.cdnService = CDNService.baseUrl;
    expect(
      VideoUtils.getCdnUrl([
        'https://upos-sz-mirror14b.bilivideo.com${_sig}14b',
        'https://upos-sz-mirrorcos.bilivideo.com${_sig}cos',
      ]),
      'https://upos-sz-mirrorcos.bilivideo.com${_sig}cos',
    );
  });

  test('关闭屏蔽时保持原来的行为', () {
    VideoUtils.blockP2p = false;
    expect(
      VideoUtils.getCdnUrl([
        'https://upos-sz-mirror14b.bilivideo.com${_sig}14b',
        'https://upos-sz-mirrorcos.bilivideo.com${_sig}cos',
      ]),
      'https://upos-sz-mirror14b.bilivideo.com${_sig}14b',
    );
  });

  test('直播：默认线路是 PCDN 时换成官方线路，手选的线路保留', () {
    final codec = CodecItem(
      currentQn: LiveQuality.values.first,
      acceptQn: const [],
      baseUrl: '/live-bvc/1/live_1.flv?',
      urlInfo: [
        UrlInfo(host: 'https://xy1x2xy.mcdn.bilivideo.cn:4483', extra: 'a=1'),
        UrlInfo(host: 'https://d1--cn-gotcha208.bilivideo.com', extra: 'a=2'),
      ],
    );
    expect(
      VideoUtils.getLiveCdnUrl(codec),
      'https://d1--cn-gotcha208.bilivideo.com/live-bvc/1/live_1.flv?a=2',
    );
    expect(
      VideoUtils.getLiveCdnUrl(codec, index: 1),
      'https://d1--cn-gotcha208.bilivideo.com/live-bvc/1/live_1.flv?a=2',
    );
    VideoUtils.blockP2p = false;
    expect(
      VideoUtils.getLiveCdnUrl(codec),
      'https://xy1x2xy.mcdn.bilivideo.cn:4483/live-bvc/1/live_1.flv?a=1',
    );
  });
}
