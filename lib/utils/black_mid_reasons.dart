import 'package:PiliPlus/utils/black_mid_rules.dart';
import 'package:PiliPlus/utils/storage.dart';

/// Why a UID is in the local blacklist: a reason typed when adding it by
/// hand, or the `uid #reason` comment of an online rule list.
abstract final class BlackMidReasons {
  static const _storageKey = 'blackMidReasons';

  static Map<int, String>? _local;
  static Map<int, ({String reason, String url})>? _rules;

  static Map<int, String> get _localMap => _local ??= _loadLocal();

  static Map<int, String> _loadLocal() {
    final raw = GStorage.localCache.get(_storageKey);
    if (raw is! Map) return {};
    return {
      for (final e in raw.entries)
        if (e.key case final int k)
          if (e.value case final String v) k: v,
    };
  }

  static Map<int, ({String reason, String url})> get _ruleMap => _rules ??= {
    for (final rule in BlackMidRules.load().reversed)
      for (final e in rule.reasons.entries)
        e.key: (reason: e.value, url: rule.url),
  };

  /// The reason for [mid] and where it came from (`url` is null for a
  /// manually added one), or null if there is none.
  static ({String reason, String? url})? of(int mid) {
    if (_localMap[mid] case final reason?) return (reason: reason, url: null);
    if (_ruleMap[mid] case final r?) return (reason: r.reason, url: r.url);
    return null;
  }

  /// The manually entered reason for [mid].
  static String? local(int mid) => _localMap[mid];

  /// Sets (or with an empty / null [reason], clears) the manual reason.
  static void setLocal(int mid, String? reason) {
    reason = reason?.trim();
    final map = _localMap;
    if (reason == null || reason.isEmpty) {
      if (map.remove(mid) == null) return;
    } else {
      if (map[mid] == reason) return;
      map[mid] = reason;
    }
    GStorage.localCache.put(_storageKey, map);
  }

  /// Rule reasons changed (a rule was updated or removed).
  static void invalidateRules() => _rules = null;
}
