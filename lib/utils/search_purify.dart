import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

/// Search result purification, ported from bilibili-search-purify
/// (https://github.com/houliabc/bilibili-search-purify, MIT, © 2026 厚礼):
///
/// - relevance: a video is kept only if its title contains the keyword, or
///   any two consecutive characters of it (after dropping stop words,
///   punctuation and case)
/// - built-in title word list (suggestive content, clickbait, stale memes,
///   insults, ads / scams, fortune telling, violence); a word that the
///   keyword itself contains is not applied, so searching for it still works
/// - a page whose results would all be hidden is shown unfiltered when it
///   is the first page (no blank result page)
abstract final class SearchPurify {
  static bool relevance = Pref.searchPurifyRelevance;
  static bool banWords = Pref.searchPurifyBanWords;

  /// user words for titles / UP names (regex, empty = off)
  static RegExp titleRegExp = RegExp(
    Pref.banWordForSearch,
    caseSensitive: false,
  );
  static RegExp upRegExp = RegExp(
    Pref.banWordForSearchUp,
    caseSensitive: false,
  );

  static final _stopWords = RegExp(
    '的|了|也|都|是|在|与|和|或|并|而|及|以及|怎么|如何|为什么|什么|居然|竟然|'
    '原来是|居然是|啊|呀|吧|呢|吗',
  );
  static final _punctuation = RegExp(
    r'''[\s,，.。!！?？、；：:;"'“”‘’()（）【】\[\]+\-—_/\\|~`@#$%^&*=]''',
  );

  /// Lower case, without stop words, punctuation and spaces.
  static String clean(String text) => text
      .toLowerCase()
      .replaceAll(_stopWords, '')
      .replaceAll(_punctuation, '');

  /// Whether [title] is related to [keyword].
  static bool isRelevant(String title, String keyword) {
    final k = clean(keyword);
    if (k.isEmpty) return true;
    final t = clean(title);
    if (t.contains(k)) return true;
    if (k.length == 1) return false;
    for (var i = 0; i + 2 <= k.length; i++) {
      if (t.contains(k.substring(i, i + 2))) return true;
    }
    return false;
  }

  /// The first built-in word in [title], unless the [keyword] has it too.
  static String? bannedWord(String title, String keyword) {
    for (final word in _words) {
      if (word.hasMatch(title) && !word.hasMatch(keyword)) return word.pattern;
    }
    return null;
  }

  /// Whether [item] would be hidden for [keyword].
  static bool shouldHide(SearchVideoItemModel item, String keyword) {
    final title = item.title;
    if (relevance && keyword.trim().isNotEmpty && !isRelevant(title, keyword)) {
      return true;
    }
    if (banWords && bannedWord(title, keyword) != null) return true;
    if (titleRegExp.pattern.isNotEmpty && titleRegExp.hasMatch(title)) {
      return true;
    }
    return upRegExp.pattern.isNotEmpty &&
        upRegExp.hasMatch(item.owner.name ?? '');
  }

  /// [list] without the hidden results. For the first page ([isFirst]),
  /// everything is kept rather than leaving the results blank.
  static List<SearchVideoItemModel> filter(
    List<SearchVideoItemModel> list,
    String keyword, {
    required bool isFirst,
  }) {
    if (!relevance &&
        !banWords &&
        titleRegExp.pattern.isEmpty &&
        upRegExp.pattern.isEmpty) {
      return list;
    }
    final kept = list.where((e) => !shouldHide(e, keyword)).toList();
    if (kept.isEmpty && isFirst) return list;
    return kept;
  }

  static final List<RegExp> _words = [
    // 擦边 / 软色情
    '姿势', r'坚持\d+分钟', '好色', '畜生', '擦边', '福利', '漏', '丝袜', '黑丝',
    '白丝', '性感', '走光', '露底', '诱惑', '大长腿', '腿控', '足控', '烧鸡',
    '懂的都懂', '老司机', '车牌', '福利姬', '深夜', '女友', '绿茶', '肉丝', '网袜',
    '蕾丝', '深V', '事业线', '真空', '凸点', '私拍', '挑逗', '调情', '情趣', '内衣',
    '睡衣', '泳装', '比基尼', '火辣', '暴露', '清凉', '撩人', '魅惑', '玉足',
    '软色情', '擦边球', '打擦边', '私密', '私处', '暧昧', '技师',
    // 夸张标题党
    '震惊', '颠覆认知', '离谱', '天花板', '破防', '绝绝子', '封神', '吓尿', '看呆',
    '看傻', '千万不要', '删前速看', '全网最', '史诗级', '吊打', '秒杀', '惊呆',
    '泪目', '毁三观', '避雷', '这谁顶得住', '这你受得了吗', '谁能拒绝', '谁懂啊',
    '家人们', '血压', '炸了', '疯了', '绝了', 'yyds', '救命', '震碎三观',
    '大开眼界', '万万没想到', '你敢信', '破大防', '蚌埠住了', '无语死了', '杀疯了',
    '卷疯了', '赢麻了', '输麻了', '神级', '顶级', '碾压', '史上最强', '全网第一',
    '世界顶级', '刷新认知', '不敢相信', '难以置信', '突发', '紧急', '重磅', '炸锅',
    '沸腾', '慌了', '懵了', '傻了', '哭了', '笑不活了', '笑死人', '大型社死',
    '社会性死亡', '离谱到家', '天花板级', '必看', '必知', '不看后悔', '错过后悔',
    '出大事了', '轰动全国', '99%的人不知道',
    // 无聊烂梗
    '少爷梦', '大型纪录片', '不要笑', '人类早期', '珍贵影像', '补档', '防失联', '某音',
    '某手', '纯爱战士', '牛头人', '大型纪录片之', '传奇', '注意看', '这个男人叫小帅',
    '这个女人叫小美', '佛波勒', '退退退', '挖呀挖', '听我说谢谢你', '奥利给',
    '双击666', '老铁', '集美', '咱就是说', '一整个', '尊嘟假嘟', '泰裤辣', '耶斯莫拉',
    '我太难了', 'emo', '摆烂', '躺平', '打工人', '搬砖', '摸鱼', '划水', '没毛病',
    '干就完了',
    // 辱骂
    '脑残', '智障', '废物', '垃圾', '人渣', '败类', '杂种', '狗东西', '王八蛋', '兔崽子',
    '贱人', '去死', '该死', '菜鸡', '辣鸡', '弱鸡', 'fw', 'nt', 'sb', '屌丝', '网暴',
    '人肉搜索',
    // 引流 / 带货 / 诈骗
    '免费送', '点赞领', '关注领', '评论领', '私信领', '加微信', '加v', 'vx', '扣扣',
    'qq', '联系方式', '私下', '私聊', '私我', '加好友', '扫码', '二维码', '小黄车',
    '橱窗', '下单', '带货', '直播带货', '赚大钱', '暴富', '发财', '兼职', '日结',
    '在家赚钱', '月入过万', '轻松赚钱', '零成本', '无门槛', '创业', '加盟', '代理',
    '微商', '刷单', '跑分', '赌博', '博彩', '彩票', '赌球', '下注', '回本', '上岸',
    '网贷', '贷款', '高利贷', '套路贷', '校园贷', '私下转账', '线下交易', '进群',
    // 迷信 / 虚假宣传
    '算命', '算卦', '风水', '占卜', '八字', '招财', '旺运', '辟邪', '镇宅', '转运',
    '改运势', '求姻缘', '化解小人', '逢凶化吉', '根治', '百分百见效', '无效退款',
    '终身保修', '零风险', '包治百病',
    // 暴力 / 违法
    '血腥', '暴力', '打人', '打架', '自杀', '自残', '跳楼', '割腕', '上吊', '毒品',
    '吸毒', '贩毒', '枪支', '管制刀具', '炸药',
  ].map((e) => RegExp(e, caseSensitive: false)).toList();
}
