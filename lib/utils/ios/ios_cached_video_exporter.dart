import 'dart:io';

import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as path;

abstract final class IosCachedVideoExporter {
  static const _channel = MethodChannel('com.piliplus/cached_video_export');

  static ({String video, String? audio})? filesFor(
    BiliDownloadEntryInfo entry,
  ) {
    final typeTag = entry.typeTag;
    if (!entry.isCompleted || typeTag == null || typeTag.isEmpty) {
      return null;
    }

    final directory = path.join(entry.entryDirPath, typeTag);
    final isMp4 = entry.mediaType == 1;
    return (
      video: path.join(
        directory,
        isMp4 ? PathUtils.videoNameType1 : PathUtils.videoNameType2,
      ),
      audio: !isMp4 && entry.hasDashAudio
          ? path.join(directory, PathUtils.audioNameType2)
          : null,
    );
  }

  static Future<void> export(BiliDownloadEntryInfo entry) async {
    if (!Platform.isIOS) return;

    final files = filesFor(entry);
    if (files == null) {
      SmartDialog.showToast('缓存尚未完成，无法导出');
      return;
    }
    if (!File(files.video).existsSync() ||
        (files.audio != null && !File(files.audio!).existsSync())) {
      SmartDialog.showToast('缓存文件不完整，无法导出');
      return;
    }

    SmartDialog.showLoading(msg: files.audio == null ? '正在准备导出' : '正在合并音视频');
    try {
      final saved =
          await _channel.invokeMethod<bool>('export', {
            'videoPath': files.video,
            'audioPath': files.audio,
            'fileName': '${entry.showTitle}.mp4',
          }) ??
          false;
      SmartDialog.dismiss();
      if (saved) SmartDialog.showToast('导出成功');
    } on PlatformException catch (error) {
      SmartDialog.dismiss();
      SmartDialog.showToast('导出失败：${error.message ?? error.code}');
    } catch (error) {
      SmartDialog.dismiss();
      SmartDialog.showToast('导出失败：$error');
    }
  }
}
