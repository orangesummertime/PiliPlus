import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/utils/ios/ios_cached_video_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

BiliDownloadEntryInfo entry({
  required int mediaType,
  bool hasDashAudio = false,
  bool isCompleted = true,
  String? typeTag = '80',
}) => BiliDownloadEntryInfo(
  mediaType: mediaType,
  hasDashAudio: hasDashAudio,
  isCompleted: isCompleted,
  totalBytes: 0,
  downloadedBytes: 0,
  title: 'test',
  typeTag: typeTag,
  cover: '',
  preferedVideoQuality: 80,
  guessedTotalBytes: 0,
  totalTimeMilli: 0,
  danmakuCount: 0,
  avid: 1,
  bvid: 'BV1',
)..entryDirPath = '/cache/entry';

void main() {
  test('completed single-file cache resolves to 0.mp4', () {
    expect(IosCachedVideoExporter.filesFor(entry(mediaType: 1)), (
      video: '/cache/entry/80/0.mp4',
      audio: null,
    ));
  });

  test('DASH cache resolves separate video and audio files', () {
    expect(
      IosCachedVideoExporter.filesFor(
        entry(mediaType: 2, hasDashAudio: true),
      ),
      (
        video: '/cache/entry/80/video.m4s',
        audio: '/cache/entry/80/audio.m4s',
      ),
    );
  });

  test('video-only DASH cache does not require an audio file', () {
    expect(
      IosCachedVideoExporter.filesFor(entry(mediaType: 2))?.audio,
      isNull,
    );
  });

  test('incomplete cache cannot be exported', () {
    expect(
      IosCachedVideoExporter.filesFor(
        entry(mediaType: 2, isCompleted: false),
      ),
      isNull,
    );
    expect(
      IosCachedVideoExporter.filesFor(entry(mediaType: 2, typeTag: null)),
      isNull,
    );
  });
}
