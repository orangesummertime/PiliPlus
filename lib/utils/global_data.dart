import 'package:PiliPlus/utils/black_mid_rules.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;

class GlobalData {
  int imgQuality = Pref.picQuality;

  num? coins;

  void afterCoin(num coin) {
    if (coins != null) {
      coins = coins! - coin;
    }
  }

  /// UIDs blocked by hand (or synced from the account); online rule lists
  /// are kept apart, see [isBlackMid].
  Set<int> blackMids = Pref.blackMids;

  /// UIDs never treated as blocked: the whitelist beats the local blacklist
  /// and the online rule lists.
  Set<int> whiteMids = Pref.whiteMids;

  /// Bumped whenever the blacklist, the whitelist or a rule list changes,
  /// so badges showing a user's status can update in place.
  final midListsRevision = ValueNotifier(0);

  void midListsChanged() => midListsRevision.value++;

  /// Whether [mid] is blocked locally or by an online UID rule, and not
  /// whitelisted.
  bool isBlackMid(Object? mid) =>
      mid is int &&
      !whiteMids.contains(mid) &&
      (blackMids.contains(mid) || BlackMidRules.contains(mid));

  bool dynamicsWaterfallFlow = Pref.dynamicsWaterfallFlow;

  bool showMedal = Pref.showMedal;

  // 私有构造函数
  GlobalData._();

  // 单例实例
  static final GlobalData _instance = GlobalData._();

  // 获取全局实例
  factory GlobalData() => _instance;
}

extension IterableExt<E> on Iterable<E> {
  Iterable<E> whereNotBlocked(Object? /* mid */ Function(E element) test) =>
      where((e) => !GlobalData().isBlackMid(test(e)));
}
