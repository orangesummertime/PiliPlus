import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/http/fav.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';

class FavReplyController extends CommonListController<List<ReplyInfo>, ReplyInfo> {
  static const _pageSize = 20;

  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  Future<LoadingState<List<ReplyInfo>>> customGetData() =>
      FavHttp.favReply(page: page, pageSize: _pageSize);

  @override
  void checkIsEnd(int length) {
    if (length < page * _pageSize) {
      isEnd = true;
    }
  }
}
