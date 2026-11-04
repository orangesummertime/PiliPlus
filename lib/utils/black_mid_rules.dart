import 'dart:convert' show LineSplitter, jsonDecode, jsonEncode, utf8;
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/utils/black_mid_store.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show compute, debugPrint, kDebugMode, visibleForTesting;
import 'package:path/path.dart' as path;

/// An online UID rule list. Its UIDs live in a [BlackMidStore] file of their
/// own and are checked alongside the local blacklist; they are not copied
/// into it.
///
/// Two kinds of list are supported:
/// - a plain txt list (`uid #reason` per line), downloaded whole; skipped
///   when the server answers 304 or the content did not change
/// - an incremental list: a `manifest.json` (format 1) pointing at a gzip
///   snapshot and cumulative deltas from older versions
class BlackMidRule {
  BlackMidRule({
    required this.url,
    this.count = 0,
    this.manifest = false,
    this.version,
    this.etag,
    this.lastModified,
    this.hash,
    this.updatedAt,
    this.changedAt,
    this.error,
  });

  final String url;

  /// UIDs in the list
  int count;

  /// an incremental list (manifest.json)
  bool manifest;

  /// manifest version the local copy is at
  int? version;

  /// validators of the last response, for conditional requests
  String? etag;
  String? lastModified;

  /// content hash of the last txt download
  String? hash;

  /// epoch milliseconds of the last successful check / last change
  int? updatedAt;
  int? changedAt;

  /// last update error, null if it succeeded
  String? error;

  factory BlackMidRule.fromJson(Map<String, dynamic> json) => BlackMidRule(
    url: json['url'] as String,
    count: json['count'] as int? ?? 0,
    manifest: json['manifest'] as bool? ?? false,
    version: json['version'] as int?,
    etag: json['etag'] as String?,
    lastModified: json['lastModified'] as String?,
    hash: json['hash'] as String?,
    updatedAt: json['updatedAt'] as int?,
    changedAt: json['changedAt'] as int?,
    error: json['error'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    'count': count,
    if (manifest) 'manifest': true,
    'version': ?version,
    'etag': ?etag,
    'lastModified': ?lastModified,
    'hash': ?hash,
    'updatedAt': ?updatedAt,
    'changedAt': ?changedAt,
    'error': ?error,
  };
}

/// Result of updating one rule.
typedef _Change = ({int added, int removed});

abstract final class BlackMidRules {
  static const _storageKey = 'blackMidRules';
  static const _txtInterval = Duration(days: 1);
  static const _manifestInterval = Duration(hours: 1);

  static final _spaceUrlRegExp = RegExp(r'space\.bilibili\.com/(\d+)');
  static final _separatorRegExp = RegExp(r'[\s,;，；、|]+');
  static final _digitsRegExp = RegExp(r'^\d{1,19}$');

  /// `!` and `//` start a comment at line begin or after whitespace (so the
  /// `//` in `https://` is kept); `#` starts one anywhere
  static final _commentRegExp = RegExp(r'#|(?:^|\s)(?:!|//)');

  /// serializes load-modify-save so auto update and manual actions don't race
  static Future<void> _queue = Future.value();

  static Future<T> _locked<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  static List<BlackMidRule> _rules = [];
  static final Map<String, BlackMidStore> _stores = {};

  /// The rules (after [init]).
  static List<BlackMidRule> get rules => _rules;

  @visibleForTesting
  static String? debugStoreDir;

  static String get _storeDir =>
      debugStoreDir ?? path.join(appSupportDirPath, 'black_mid_rules');

  static String _storePath(String url) {
    // FNV-1a, enough to give each rule its own file name
    var h = 0xcbf29ce484222325;
    for (final c in utf8.encode(url)) {
      h = (h ^ c) * 0x100000001b3;
    }
    return path.join(
      _storeDir,
      '${h.toUnsigned(64).toRadixString(16)}.bin',
    );
  }

  /// Whether any rule lists [mid].
  static bool contains(int mid) {
    for (final store in _stores.values) {
      if (store.contains(mid)) return true;
    }
    return false;
  }

  /// The URL of the first rule that lists [mid].
  static String? sourceOf(int mid) {
    for (final MapEntry(key: url, value: store) in _stores.entries) {
      if (store.contains(mid)) return url;
    }
    return null;
  }

  /// The reason a rule gives for [mid], and that rule's URL.
  static ({String reason, String url})? reasonOf(int mid) {
    for (final MapEntry(key: url, value: store) in _stores.entries) {
      if (store.reasonOf(mid) case final reason?) {
        return (reason: reason, url: url);
      }
    }
    return null;
  }

  // ---- persistence ----

  static bool _initialized = false;

  /// Loads the rules and their UID files. Call once on start.
  static Future<void> init() => _locked(() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final raw = GStorage.localCache.get(_storageKey);
      if (raw is! String || raw.isEmpty) return;
      final list = await compute(_decodeJson, raw);
      if (list.any((e) => e.containsKey('mids'))) {
        await _migrate(list);
        return;
      }
      _rules = list.map(BlackMidRule.fromJson).toList();
      final stores = await Future.wait(
        _rules.map((e) => compute(_readStore, _storePath(e.url))),
      );
      for (var i = 0; i < _rules.length; i++) {
        if (stores[i] case final store?) {
          _stores[_rules[i].url] = store;
        } else {
          // the file is gone: download it again on the next update
          _rules[i]
            ..resetValidators()
            ..updatedAt = null;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('BlackMidRules init: $e');
    }
  });

  static List<Map<String, dynamic>> _decodeJson(String raw) =>
      (jsonDecode(raw) as List).cast<Map<String, dynamic>>();

  static BlackMidStore? _readStore(String file) {
    try {
      return BlackMidStore.fromBytes(File(file).readAsBytesSync());
    } catch (_) {
      return null;
    }
  }

  static void _writeStore((String, BlackMidStore) args) {
    final (file, store) = args;
    File('$file.tmp')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(store.toBytes(), flush: true)
      ..renameSync(file);
  }

  static Future<void> _saveRules() => GStorage.localCache.put(
    _storageKey,
    jsonEncode(_rules.map((e) => e.toJson()).toList()),
  );

  static Future<void> _setStore(String url, BlackMidStore store) async {
    await compute(_writeStore, (_storePath(url), store));
    _stores[url] = store;
  }

  /// Rules used to copy their UIDs into the local blacklist (and remember
  /// the ones they added as `owned`). Take those back out and move every
  /// list into its own store.
  static Future<void> _migrate(List<Map<String, dynamic>> list) async {
    final blackMids = GlobalData().blackMids;
    for (final json in list) {
      final url = json['url'] as String;
      final mids = (json['mids'] as List? ?? const []).cast<int>();
      final owned = (json['owned'] as List? ?? const []).cast<int>();
      final reasons = <int, String>{
        for (final MapEntry(:key, :value)
            in ((json['reasons'] as Map?) ?? const {}).entries)
          int.parse(key as String): value as String,
      };
      blackMids.removeAll(owned);
      final store = await compute(
        _buildStore,
        (mids: mids.toSet(), reasons: reasons),
      );
      await _setStore(url, store);
      _rules.add(
        BlackMidRule(
          url: url,
          count: store.length,
          updatedAt: json['updatedAt'] as int?,
          changedAt: json['updatedAt'] as int?,
          error: json['error'] as String?,
        ),
      );
    }
    Pref.blackMids = blackMids;
    await _saveRules();
  }

  static BlackMidStore _buildStore(
    ({Set<int> mids, Map<int, String> reasons}) parsed,
  ) => BlackMidStore.build(parsed.mids, parsed.reasons);

  // ---- parsing ----

  /// Normalizes user input to an http(s) URL, or null if invalid.
  static String? normalizeUrl(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasAuthority) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri.toString();
  }

  /// Parses a txt rule list.
  ///
  /// One or more UIDs per line, separated by spaces / commas / semicolons.
  /// `#`, `//` and `!` start a comment. A `space.bilibili.com/<uid>` link
  /// counts as its UID. Anything else is ignored.
  static Set<int> parse(String text) => parseWithReasons(text).mids;

  /// Like [parse], also returning the inline comment of each UID line
  /// (`123456 #reason`) as that UID's reason.
  static ({Set<int> mids, Map<int, String> reasons}) parseWithReasons(
    String text,
  ) {
    final mids = <int>{};
    final reasons = <int, String>{};
    for (var line in const LineSplitter().convert(text)) {
      String? reason;
      if (_commentRegExp.firstMatch(line) case final m?) {
        reason = line.substring(m.end).trim();
        line = line.substring(0, m.start);
      }
      line = line.trim();
      if (line.isEmpty) continue;

      final lineMids = <int>[];
      final spaceMatches = _spaceUrlRegExp.allMatches(line);
      if (spaceMatches.isNotEmpty) {
        for (final m in spaceMatches) {
          final mid = int.tryParse(m.group(1)!);
          if (mid != null && mid > 0) lineMids.add(mid);
        }
      } else {
        for (final token in line.split(_separatorRegExp)) {
          if (!_digitsRegExp.hasMatch(token)) continue;
          final mid = int.tryParse(token);
          if (mid != null && mid > 0) lineMids.add(mid);
        }
      }
      mids.addAll(lineMids);
      if (reason != null && reason.isNotEmpty) {
        for (final mid in lineMids) {
          reasons.putIfAbsent(mid, () => reason!);
        }
      }
    }
    return (mids: mids, reasons: reasons);
  }

  /// Parses a delta: `+uid` / `+uid #reason` adds a UID or sets its reason,
  /// `-uid` removes it. Throws on anything else.
  @visibleForTesting
  static ({Map<int, String?> adds, Set<int> removes}) parseDelta(String text) {
    final adds = <int, String?>{};
    final removes = <int>{};
    var n = 0;
    for (final raw in const LineSplitter().convert(text)) {
      n++;
      final line = raw.trim();
      if (line.isEmpty) continue;
      final op = line[0];
      var rest = line.substring(1);
      String? reason;
      if (op == '+') {
        final i = rest.indexOf('#');
        if (i != -1) {
          reason = rest.substring(i + 1).trim();
          rest = rest.substring(0, i);
        }
      } else if (op != '-') {
        throw FormatException('bad delta line $n');
      }
      rest = rest.trim();
      final mid = _digitsRegExp.hasMatch(rest) ? int.tryParse(rest) : null;
      if (mid == null || mid <= 0) throw FormatException('bad delta line $n');
      if (op == '+') {
        adds[mid] = reason == null || reason.isEmpty ? null : reason;
        removes.remove(mid);
      } else {
        removes.add(mid);
        adds.remove(mid);
      }
    }
    return (adds: adds, removes: removes);
  }

  static Uint8List _gunzip(Uint8List bytes) =>
      bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b
      ? Uint8List.fromList(gzip.decode(bytes))
      : bytes;

  static String _text(Uint8List bytes) =>
      utf8.decode(_gunzip(bytes), allowMalformed: true);

  /// Builds the store of a full list (txt or snapshot); also counts the
  /// UIDs added / removed compared with [old].
  static (BlackMidStore, _Change) _buildFull(
    (Uint8List bytes, BlackMidStore old) args,
  ) {
    final parsed = parseWithReasons(_text(args.$1));
    final store = BlackMidStore.build(parsed.mids, parsed.reasons);
    return (store, _diff(args.$2, store));
  }

  static (BlackMidStore, _Change) _applyDelta(
    (Uint8List bytes, BlackMidStore old) args,
  ) {
    final delta = parseDelta(_text(args.$1));
    final store = args.$2.apply(delta.adds, delta.removes);
    return (store, _diff(args.$2, store));
  }

  static _Change _diff(BlackMidStore a, BlackMidStore b) {
    var removed = 0;
    for (final (mid, _) in a.entries) {
      if (!b.contains(mid)) removed++;
    }
    return (added: b.length - a.length + removed, removed: removed);
  }

  /// FNV-1a of the downloaded bytes, to skip unchanged txt lists.
  static String _hash(Uint8List bytes) {
    var h = 0xcbf29ce484222325;
    for (final c in bytes) {
      h = (h ^ c) * 0x100000001b3;
    }
    return '${bytes.length}-${h.toUnsigned(64).toRadixString(16)}';
  }

  // ---- updating ----

  static Dio _dio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 2),
      responseType: ResponseType.bytes,
      // a plain client: never send the Bilibili cookies to third-party hosts
      headers: {'user-agent': BrowserUa.platform},
      validateStatus: (status) => status == 200 || status == 304,
    ),
  );

  static Future<Response<Uint8List>> _get(
    Dio dio,
    String url, {
    BlackMidRule? conditional,
  }) => dio.get<Uint8List>(
    url,
    options: Options(
      headers: {
        'if-none-match': ?conditional?.etag,
        'if-modified-since': ?conditional?.lastModified,
      },
    ),
  );

  static Uint8List _body(Response<Uint8List> res) => res.data ?? Uint8List(0);

  static bool _looksLikeJson(Uint8List bytes) {
    for (final c in bytes) {
      if (c == 0x20 ||
          c == 0x0a ||
          c == 0x0d ||
          c == 0x09 ||
          c == 0xef ||
          c == 0xbb ||
          c == 0xbf) {
        continue; // whitespace / BOM
      }
      return c == 0x7b; // {
    }
    return false;
  }

  /// Updates one rule. Returns null when nothing changed.
  static Future<_Change?> _updateRule(BlackMidRule rule) async {
    final dio = _dio();
    try {
      final old = _stores[rule.url] ?? BlackMidStore.empty;
      final hasData = _stores.containsKey(rule.url);
      final res = await _get(
        dio,
        rule.url,
        conditional: hasData ? rule : null,
      );
      if (res.statusCode == 304) return null;
      final bytes = _body(res);
      final etag = res.headers.value('etag');
      final lastModified = res.headers.value('last-modified');

      _Change? change;
      if (_looksLikeJson(bytes)) {
        change = await _updateManifest(dio, rule, bytes, old, hasData);
      } else {
        final hash = await compute(_hash, bytes);
        if (!hasData || rule.manifest || hash != rule.hash) {
          final (store, diff) = await compute(_buildFull, (bytes, old));
          await _setStore(rule.url, store);
          rule
            ..manifest = false
            ..version = null
            ..count = store.length;
          change = diff;
        }
        rule.hash = hash;
      }
      rule
        ..etag = etag
        ..lastModified = lastModified;
      return change;
    } finally {
      dio.close(force: true);
    }
  }

  static Future<_Change?> _updateManifest(
    Dio dio,
    BlackMidRule rule,
    Uint8List bytes,
    BlackMidStore old,
    bool hasData,
  ) async {
    final Map<String, dynamic> manifest;
    try {
      manifest = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('manifest 不是有效的 JSON');
    }
    if (manifest['format'] != 1) {
      throw FormatException('不支持的格式 ${manifest['format']}');
    }
    final version = manifest['version'] as int;
    final count = manifest['count'] as int;
    final base = Uri.parse(rule.url);
    String resolve(Map<String, dynamic> file) =>
        base.resolve(file['url'] as String).toString();

    if (hasData && rule.manifest && rule.version == version) return null;

    (BlackMidStore, _Change)? result;
    // cumulative delta from the local version, if the publisher still has it
    if (hasData && rule.manifest && rule.version != null) {
      final delta =
          (manifest['deltas'] as Map?)?['${rule.version}']
              as Map<String, dynamic>?;
      if (delta != null) {
        try {
          final res = await _get(dio, resolve(delta));
          final r = await compute(_applyDelta, (_body(res), old));
          if (r.$1.length == count) result = r;
        } catch (e) {
          if (kDebugMode) debugPrint('BlackMidRules delta: $e');
        }
      }
    }
    // otherwise (or if the delta did not add up) the full snapshot
    if (result == null) {
      final snapshot = manifest['snapshot'] as Map<String, dynamic>;
      final res = await _get(dio, resolve(snapshot));
      final full = await compute(_buildFull, (_body(res), old));
      if (full.$1.length != count) {
        throw FormatException(
          '校验失败：快照 ${full.$1.length} 条，清单 $count 条',
        );
      }
      result = full;
    }
    await _setStore(rule.url, result.$1);
    rule
      ..manifest = true
      ..version = version
      ..hash = null
      ..count = count;
    return result.$2;
  }

  /// Adds rule URLs (duplicates and invalid ones skipped) and updates them.
  /// Returns a short summary for a toast.
  static Future<String> addAndUpdate(Iterable<String> inputs) =>
      _locked(() async {
        final existing = _rules.map((e) => e.url).toSet();
        final added = <BlackMidRule>[];
        var invalid = 0;
        for (final input in inputs) {
          final url = normalizeUrl(input);
          if (url == null) {
            if (input.trim().isNotEmpty) invalid++;
            continue;
          }
          if (existing.add(url)) {
            final rule = BlackMidRule(url: url);
            _rules.add(rule);
            added.add(rule);
          }
        }
        if (added.isEmpty) {
          return invalid > 0 ? '链接无效' : '没有新的规则';
        }
        await _saveRules();
        final summary = await _updateRules(added);
        return invalid > 0 ? '$summary，$invalid 个链接无效' : summary;
      });

  /// Updates the given rules (all if null). Returns a summary for a toast.
  static Future<String> update([Iterable<String>? urls]) => _locked(() {
    final targets = urls == null
        ? _rules
        : _rules.where((e) => urls.contains(e.url)).toList();
    if (targets.isEmpty) return Future.value('没有规则');
    return _updateRules(targets);
  });

  static Future<String> _updateRules(List<BlackMidRule> targets) async {
    var added = 0;
    var removed = 0;
    var changed = 0;
    var failed = 0;
    // one by one: the lists can be large, and the server may rate limit
    for (final rule in targets) {
      try {
        final change = await _updateRule(rule);
        final now = DateTime.now().millisecondsSinceEpoch;
        rule
          ..updatedAt = now
          ..error = null;
        if (change != null) {
          rule.changedAt = now;
          changed++;
          added += change.added;
          removed += change.removed;
        }
      } catch (e) {
        rule.error = e is DioException ? e.message ?? '${e.type}' : '$e';
        failed++;
      }
    }
    await _saveRules();

    final ok = targets.length - failed;
    final parts = <String>[
      if (ok > 0)
        changed == 0
            ? '$ok 个规则无变化'
            : '更新 $changed 个规则，新增 $added 个 UID'
                  '${removed > 0 ? '，移除 $removed 个' : ''}',
      if (failed > 0) '$failed 个失败',
    ];
    return parts.join('，');
  }

  /// Removes a rule; its UIDs stop counting as blocked.
  static Future<void> remove(String url) => _locked(() async {
    _rules.removeWhere((e) => e.url == url);
    _stores.remove(url);
    await _saveRules();
    try {
      await File(_storePath(url)).delete();
    } catch (_) {}
  });

  /// Called on app start (after [init]): refreshes rules that are due —
  /// incremental lists hourly (the manifest is tiny), txt lists daily.
  static Future<void> autoUpdate() => _locked(() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final due = _rules.where((e) {
        final interval = e.manifest ? _manifestInterval : _txtInterval;
        return e.updatedAt == null ||
            now - e.updatedAt! > interval.inMilliseconds;
      }).toList();
      if (due.isEmpty) return;
      await _updateRules(due);
    } catch (e) {
      if (kDebugMode) debugPrint('BlackMidRules autoUpdate: $e');
    }
  });

  @visibleForTesting
  static void debugReset() {
    _rules = [];
    _stores.clear();
    _initialized = false;
  }
}

extension on BlackMidRule {
  void resetValidators() {
    etag = null;
    lastModified = null;
    hash = null;
    version = null;
  }
}
