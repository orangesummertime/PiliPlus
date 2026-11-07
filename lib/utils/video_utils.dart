import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/models/common/video/cdn_type.dart';
import 'package:PiliPlus/models/common/video/video_decode_type.dart';
import 'package:PiliPlus/models/video/play/url.dart'
    show AudioItem, VideoItem, FormatItem;
import 'package:PiliPlus/models_new/live/live_room_play_info/codec.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

abstract final class VideoUtils {
  static CDNService cdnService = Pref.defaultCDNService;
  static String? liveCdnUrl = Pref.liveCdnUrl;
  static bool disableAudioCDN = Pref.disableAudioCDN;

  /// Never pick a P2P / PCDN host (setting 屏蔽 PCDN/P2P 节点).
  static bool blockP2p = Pref.blockP2pCdn;

  // P2P / PCDN hosts, from Make-Bilibili-Great-Than-Ever-Before
  // (https://github.com/SukkaW/Make-Bilibili-Great-Than-Ever-Before, MIT,
  // src/core/player/cdn-classify.ts) and the Surge rules in
  // https://x.com/gxgexiao/status/2119003466085646646
  static const _p2pHostKeywords = [
    '302ppio',
    '302kodo',
    '.mcdn.bilivideo',
    'szbdyd.com',
    '.nexusedgeio.com',
    '.ahdohpiechei.com', // 七牛云 PCDN
    '.mountaintoys.cn',
    '.bvmlt.top',
    'smtcdns.net',
    // mirror type, but its SSL cert is for PCDN (*.bilivideo.cn)
    'upos-sz-mirror14b.bilivideo.com',
  ];

  /// Whether [host] is a P2P / PCDN node.
  static bool isP2pHost(String host) {
    host = host.toLowerCase();
    for (final keyword in _p2pHostKeywords) {
      if (host.contains(keyword)) return true;
    }
    final first = host.split('.').first;
    // upos-sz-302ppio.bilivideo.com, upos-sz-302kodo...: *302* subdomain
    if (first.contains('302')) return true;
    // *pcdn*.biliapi.net
    return first.contains('pcdn') && host.endsWith('.biliapi.net');
  }

  static bool _isP2pUrl(String url) =>
      blockP2p && isP2pHost(Uri.tryParse(url)?.host ?? '');

  static const _proxyTf = 'proxy-tf-all-ws.bilivideo.com';

  static final _mirrorRegex = RegExp(
    r'^https?://(?:upos-\w+-(?!302)\w+|(?:upos|proxy)-tf-[^/]+)\.(?:bilivideo|akamaized)\.(?:com|net)/upgcxcode',
  );

  static final _mCdnTfRegex = RegExp(
    r'^https?://(?:(?:(?:\d{1,3}\.){3}\d{1,3}|[^/]+\.mcdn\.bilivideo\.(?:com|cn|net))(?:\:\d{1,5})?/v\d/resource)',
  );

  static String getCdnUrl(
    Iterable<String> urls, {
    CDNService? defaultCDNService,
    bool isAudio = false,
  }) {
    defaultCDNService ??= cdnService;

    if (defaultCDNService == CDNService.baseUrl && !_isP2pUrl(urls.first)) {
      return urls.first;
    }

    if (defaultCDNService == CDNService.akamai &&
        !(isAudio && disableAudioCDN)) {
      // Akamai URLs have their own signature (e.g. hdnts). Replacing another
      // CDN's host preserves the wrong signature and results in HTTP 403.
      // Keep the API-provided URL intact, including its encoded query string.
      return urls.firstWhere(
        (url) => Uri.tryParse(url)?.host == CDNService.akamai.host,
        orElse: () => urls.first,
      );
    }

    // audio that does not follow the CDN setting uses the backup URL
    // (lemonteaau/PiliPlus)
    final selectedCDNService = isAudio && disableAudioCDN
        ? CDNService.backupUrl
        : defaultCDNService;
    // a replacement host: never a P2P one
    final replaceHost =
        selectedCDNService.host != null &&
            !(blockP2p && isP2pHost(selectedCDNService.host!))
        ? selectedCDNService.host
        : null;

    String? mcdnTf;
    String? mcdnUpgcxcode;

    String last = '';
    for (final url in urls) {
      last = url;
      if (_mirrorRegex.hasMatch(url)) {
        final uri = Uri.parse(url);
        if (uri.queryParameters['os'] == 'mcdn' ||
            (blockP2p && isP2pHost(uri.host))) {
          // upos-sz-mirrorcoso1.bilivideo.com os=mcdn, upos-sz-mirror14b
          mcdnUpgcxcode ??= url;
        } else {
          if (replaceHost == null) {
            return url;
          }
          return uri.replace(host: replaceHost).toString();
        }
      }

      if (_mCdnTfRegex.hasMatch(url)) {
        mcdnTf = url;
        continue;
      }

      // upos-\w*-302.* & bcache & mcdn host but upgcxcode path
      if (url.contains('/upgcxcode/')) {
        mcdnUpgcxcode ??= url;
        continue;
      }

      // may be deprecated
      if (url.contains('szbdyd.com')) {
        final uri = Uri.parse(url);
        final hostname =
            uri.queryParameters['xy_usource'] ?? replaceHost ?? uri.host;
        return uri
            .replace(scheme: 'https', host: hostname, port: 443)
            .toString();
      }

      if (kDebugMode) {
        debugPrint('unknown cdn type: $url');
      }
    }

    return mcdnUpgcxcode == null
        ? mcdnTf == null
              ? last
              : Uri(
                  scheme: 'https',
                  host: _proxyTf,
                  queryParameters: {'url': mcdnTf},
                ).toString()
        : Uri.parse(mcdnUpgcxcode)
              .replace(
                scheme: 'https',
                host: replaceHost ?? CDNService.ali.host,
                port: 443,
              )
              .toString();
  }

  static String getLiveCdnUrl(CodecItem e, {int index = 0}) {
    var urlInfo = e.urlInfo.getOrFirst(index);
    // the default line is a PCDN one: take the first official line instead
    // (a line picked by hand is kept)
    if (index == 0 && blockP2p && liveCdnUrl == null) {
      bool p2p(String host) => isP2pHost(Uri.tryParse(host)?.host ?? host);
      if (p2p(urlInfo.host)) {
        urlInfo = e.urlInfo.firstWhere(
          (i) => !p2p(i.host),
          orElse: () => urlInfo,
        );
      }
    }
    return (liveCdnUrl ?? urlInfo.host) + e.baseUrl + urlInfo.extra;
  }

  static VideoDecodeFormatType selectCodec(
    Iterable<String> codecs,
    List<VideoDecodeFormatType> preferCodecs,
  ) {
    if (preferCodecs.isNotEmpty) {
      int bestIndex = preferCodecs.length;
      for (final e in codecs) {
        for (int i = 0; i < bestIndex; i++) {
          if (preferCodecs[i].codes.any(e.startsWith)) {
            bestIndex = i;
            if (bestIndex == 0) {
              return preferCodecs[0];
            }
            break;
          }
        }
      }
      if (bestIndex < preferCodecs.length) {
        return preferCodecs[bestIndex];
      }
    }
    return VideoDecodeFormatType.fromString(codecs.first);
  }

  static int _findAvailableVideoQuality(
    List<VideoItem> videoList,
    List<int>? acceptQuality,
    int preferQuality,
  ) {
    final highestVideoQa = videoList.first.id;
    if (preferQuality >= highestVideoQa) {
      return highestVideoQa;
    }

    if (acceptQuality != null && acceptQuality.isNotEmpty) {
      return acceptQuality.findTargetMedia((e) => e, preferQuality);
    }

    return videoList.findTargetMedia((e) => e.id, preferQuality).quality.code;
  }

  static (
    int targetQuality,
    FormatItem targetFormat,
    VideoDecodeFormatType targetDecode,
    VideoItem targetVideo,
  )
  findTargetVideo(
    List<VideoItem> videoList,
    int preferQuality,
    List<int>? acceptQuality,
    List<FormatItem> supportFormats,
    List<VideoDecodeFormatType> preferCodecs,
  ) {
    assert(videoList.isNotEmpty);

    final targetQuality = _findAvailableVideoQuality(
      videoList,
      acceptQuality,
      preferQuality,
    );

    final targetFormat = supportFormats.firstWhere(
      (e) => e.quality == targetQuality,
      orElse: () => supportFormats.first,
    );

    final targetDecode = VideoUtils.selectCodec(
      targetFormat.codecs!,
      preferCodecs,
    );

    final targetQaVideoList = videoList
        .where((e) => e.id == targetQuality)
        .toList();

    final targetVideo = targetQaVideoList.firstWhere(
      (e) => targetDecode.codes.any(e.codecs!.startsWith),
      orElse: () => targetQaVideoList.first,
    );

    return (targetVideo.id, targetFormat, targetDecode, targetVideo);
  }

  static AudioItem findTargetAudio(
    List<AudioItem> audioList,
    int preferQuality,
  ) {
    assert(audioList.isNotEmpty);

    final preferredRank = AudioQuality.fromCode(preferQuality).rank;
    return audioList.findTargetMedia(
      (audio) => AudioQuality.fromCode(audio.id).rank,
      preferredRank,
    );
  }
}
