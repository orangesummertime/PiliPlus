import 'dart:convert' show LineSplitter, jsonDecode, jsonEncode, utf8;

import 'package:PiliPlus/http/browser_ua.dart';
import 'package:PiliPlus/utils/black_mid_reasons.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show compute, debugPrint, kDebugMode, visibleForTesting;

/// An online UID rule list (plain text) merged into the local blacklist.
class BlackMidRule {
  BlackMidRule({
    required this.url,
    List<int>? mids,
    List<int>? owned,
    Map<int, String>? reasons,
    this.updatedAt,
    this.error,
  }) : mids = mids ?? [],
       owned = owned ?? [],
       reasons = reasons ?? {};

  final String url;

  /// every UID in the list as last downloaded
  List<int> mids;

  /// UIDs this rule actually added to the local blacklist; only these are
  /// taken back when the rule is updated or removed, so manually added /
  /// account-synced UIDs are never touched
  List<int> owned;

  /// `uid #reason` comments in the list, shown next to the 已拉黑 badge
  Map<int, String> reasons;

  /// epoch milliseconds of the last successful update
  int? updatedAt;

  /// last update error, null if it succeeded
  String? error;

  factory BlackMidRule.fromJson(Map<String, dynamic> json) => BlackMidRule(
    url: json['url'] as String,
    mids: (json['mids'] as List?)?.cast<int>(),
    owned: (json['owned'] as List?)?.cast<int>(),
    reasons: (json['reasons'] as Map?)?.map(
      (k, v) => MapEntry(int.parse(k as String), v as String),
    ),
    updatedAt: json['updatedAt'] as int?,
    error: json['error'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    'mids': mids,
    'owned': owned,
    if (reasons.isNotEmpty)
      'reasons': reasons.map((k, v) => MapEntry(k.toString(), v)),
    'updatedAt': ?updatedAt,
    'error': ?error,
  };
}

abstract final class BlackMidRules {
  static const _storageKey = 'blackMidRules';
  static const _autoUpdateInterval = Duration(days: 1);
  static const _maxBytes = 8 * 1024 * 1024;

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

  static List<BlackMidRule> load() {
    final raw = GStorage.localCache.get(_storageKey);
    if (raw is! String || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => BlackMidRule.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('BlackMidRules load: $e');
      return [];
    }
  }

  static Future<void> _save(List<BlackMidRule> rules) => GStorage.localCache
      .put(_storageKey, jsonEncode(rules.map((e) => e.toJson()).toList()));

  static void _saveBlackMids() => Pref.blackMids = GlobalData().blackMids;

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

  static Future<({Set<int> mids, Map<int, String> reasons})> _fetch(
    String url,
  ) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.bytes,
        // a plain client: never send the Bilibili cookies to third-party hosts
        headers: {'user-agent': BrowserUa.platform},
      ),
    );
    try {
      final res = await dio.get<List<int>>(url);
      final bytes = res.data ?? const <int>[];
      if (bytes.length > _maxBytes) {
        throw Exception('文件过大（超过 8MB）');
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      return await compute(parseWithReasons, text);
    } finally {
      dio.close(force: true);
    }
  }

  /// Applies a freshly downloaded list to [rule] and the local blacklist.
  /// Returns how many UIDs were newly added.
  @visibleForTesting
  static int apply(
    BlackMidRule rule,
    Set<int> newMids,
    List<BlackMidRule> rules,
    Set<int> blackMids, {
    Map<int, String>? reasons,
  }) {
    final owned = rule.owned.toSet();

    // take back UIDs this rule added that are no longer listed
    for (final mid in owned.difference(newMids)) {
      _releaseMid(mid, rule, rules, blackMids);
    }

    final newOwned = owned.intersection(newMids);
    var added = 0;
    for (final mid in newMids) {
      if (blackMids.add(mid)) {
        newOwned.add(mid);
        added++;
      }
    }

    rule
      ..mids = newMids.toList()
      ..owned = newOwned.toList()
      ..reasons = reasons ?? {}
      ..updatedAt = DateTime.now().millisecondsSinceEpoch
      ..error = null;
    return added;
  }

  /// Takes back every UID [rule] added (before the rule is deleted).
  @visibleForTesting
  static void release(
    BlackMidRule rule,
    List<BlackMidRule> rules,
    Set<int> blackMids,
  ) {
    for (final mid in rule.owned) {
      _releaseMid(mid, rule, rules, blackMids);
    }
  }

  /// Removes [mid] from the blacklist unless another rule still lists it,
  /// in which case that rule becomes its owner.
  static void _releaseMid(
    int mid,
    BlackMidRule from,
    List<BlackMidRule> rules,
    Set<int> blackMids,
  ) {
    for (final other in rules) {
      if (identical(other, from)) continue;
      if (other.mids.contains(mid)) {
        if (!other.owned.contains(mid)) other.owned.add(mid);
        return;
      }
    }
    blackMids.remove(mid);
  }

  /// Adds rule URLs (duplicates and invalid ones skipped) and updates them.
  /// Returns a short summary for a toast.
  static Future<String> addAndUpdate(Iterable<String> inputs) =>
      _locked(() => _addAndUpdate(inputs));

  static Future<String> _addAndUpdate(Iterable<String> inputs) async {
    final rules = load();
    final existing = rules.map((e) => e.url).toSet();
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
        rules.add(rule);
        added.add(rule);
      }
    }
    if (added.isEmpty) {
      return invalid > 0 ? '链接无效' : '没有新的规则';
    }
    await _save(rules);
    final summary = await _updateRules(rules, added);
    return invalid > 0 ? '$summary，$invalid 个链接无效' : summary;
  }

  /// Updates the given rules (all if null). Returns a summary for a toast.
  static Future<String> update([Iterable<String>? urls]) =>
      _locked(() => _update(urls));

  static Future<String> _update(Iterable<String>? urls) async {
    final rules = load();
    final targets = urls == null
        ? rules
        : rules.where((e) => urls.contains(e.url)).toList();
    if (targets.isEmpty) return '没有规则';
    return _updateRules(rules, targets);
  }

  static Future<String> _updateRules(
    List<BlackMidRule> rules,
    List<BlackMidRule> targets,
  ) async {
    final results = await Future.wait(
      targets.map((rule) async {
        try {
          return (rule, await _fetch(rule.url), null);
        } catch (e) {
          return (rule, null, e is DioException ? e.message ?? '$e' : '$e');
        }
      }),
    );

    var added = 0;
    var failed = 0;
    for (final (rule, parsed, error) in results) {
      if (parsed != null) {
        added += apply(
          rule,
          parsed.mids,
          rules,
          GlobalData().blackMids,
          reasons: parsed.reasons,
        );
      } else {
        rule.error = error;
        failed++;
      }
    }
    _saveBlackMids();
    await _save(rules);
    BlackMidReasons.invalidateRules();

    final ok = targets.length - failed;
    final parts = ['更新 $ok 个规则', '新增 $added 个 UID'];
    if (failed > 0) parts.add('$failed 个失败');
    return parts.join('，');
  }

  /// Removes a rule and takes back the UIDs only it added.
  static Future<void> remove(String url) => _locked(() => _remove(url));

  static Future<void> _remove(String url) async {
    final rules = load();
    final index = rules.indexWhere((e) => e.url == url);
    if (index == -1) return;
    release(rules[index], rules, GlobalData().blackMids);
    rules.removeAt(index);
    _saveBlackMids();
    await _save(rules);
    BlackMidReasons.invalidateRules();
  }

  /// Called on app start: refreshes rules not updated within a day.
  static Future<void> autoUpdate() => _locked(_autoUpdate);

  static Future<void> _autoUpdate() async {
    try {
      final rules = load();
      if (rules.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final due = rules
          .where(
            (e) =>
                e.updatedAt == null ||
                now - e.updatedAt! > _autoUpdateInterval.inMilliseconds,
          )
          .toList();
      if (due.isEmpty) return;
      await _updateRules(rules, due);
    } catch (e) {
      if (kDebugMode) debugPrint('BlackMidRules autoUpdate: $e');
    }
  }
}
