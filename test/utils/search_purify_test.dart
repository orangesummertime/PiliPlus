import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/utils/search_purify.dart';
import 'package:flutter_test/flutter_test.dart';

SearchVideoItemModel _video(String title, {String author = 'up'}) =>
    SearchVideoItemModel.fromJson({
      'title': title,
      'author': author,
      'mid': 1,
      'aid': 1,
      'bvid': 'BV1',
    });

List<String> _titles(List<SearchVideoItemModel> list) =>
    list.map((e) => e.title).toList();

void main() {
  setUp(() {
    SearchPurify.relevance = true;
    SearchPurify.banWords = true;
    SearchPurify.titleRegExp = RegExp('');
    SearchPurify.upRegExp = RegExp('');
  });

  test('强相关：含搜索词或其中任意两个连续的字', () {
    expect(SearchPurify.isRelevant('家常红烧肉做法', '红烧肉'), isTrue);
    expect(SearchPurify.isRelevant('东坡肉的做法', '红烧肉'), isFalse);
    expect(SearchPurify.isRelevant('烧肉饭', '红烧肉'), isTrue);
    expect(SearchPurify.isRelevant('今天吃火锅', '红烧肉'), isFalse);
    // stop words and punctuation are ignored
    expect(SearchPurify.isRelevant('如何学 Python？', '怎么学python'), isTrue);
    // a single character keyword
    expect(SearchPurify.isRelevant('猫猫合集', '猫'), isTrue);
    expect(SearchPurify.isRelevant('狗狗合集', '猫'), isFalse);
  });

  test('屏蔽词：命中隐藏；搜索词本身含有的词不屏蔽；不分大小写', () {
    expect(SearchPurify.bannedWord('震惊！红烧肉竟然这样做', '红烧肉'), '震惊');
    expect(SearchPurify.bannedWord('震惊部的日常', '震惊'), isNull);
    expect(SearchPurify.bannedWord('YYDS 的红烧肉', '红烧肉'), 'yyds');
    expect(SearchPurify.bannedWord('家常红烧肉', '红烧肉'), isNull);
  });

  test('过滤一页；首页全被过滤时原样显示；自定义标题/UP 主过滤', () {
    final page = [
      _video('<em class="keyword">红烧肉</em>家常做法'),
      _video('震惊！红烧肉'),
      _video('今天吃火锅'),
    ];
    expect(_titles(SearchPurify.filter(page, '红烧肉', isFirst: true)), [
      '红烧肉家常做法',
    ]);

    final allBad = [_video('今天吃火锅'), _video('奶茶测评')];
    expect(SearchPurify.filter(allBad, '红烧肉', isFirst: true), allBad);
    expect(SearchPurify.filter(allBad, '红烧肉', isFirst: false), isEmpty);

    SearchPurify.titleRegExp = RegExp('家常', caseSensitive: false);
    SearchPurify.upRegExp = RegExp('营销号', caseSensitive: false);
    final more = [
      _video('红烧肉家常做法'),
      _video('红烧肉教程', author: '某营销号'),
      _video('红烧肉教程'),
    ];
    expect(_titles(SearchPurify.filter(more, '红烧肉', isFirst: false)), [
      '红烧肉教程',
    ]);
  });

  test('关闭开关后不过滤', () {
    SearchPurify.relevance = false;
    SearchPurify.banWords = false;
    final page = [_video('震惊！今天吃火锅')];
    expect(SearchPurify.filter(page, '红烧肉', isFirst: false), page);
  });
}
