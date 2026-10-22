import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/utils/reply_floor.dart';
import 'package:material_ui/material_ui.dart';

/// `#123` at the top right of a top level comment, shown once its floor is
/// resolved (see [ReplyFloorResolver]).
class ReplyFloorTag extends StatefulWidget {
  const ReplyFloorTag({
    super.key,
    required this.resolver,
    required this.reply,
    required this.style,
  });

  final ReplyFloorResolver resolver;
  final ReplyInfo reply;
  final TextStyle style;

  @override
  State<ReplyFloorTag> createState() => _ReplyFloorTagState();
}

class _ReplyFloorTagState extends State<ReplyFloorTag> {
  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(ReplyFloorTag oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reply.id != widget.reply.id ||
        oldWidget.resolver != widget.resolver) {
      _request();
    }
  }

  void _request() => widget.resolver.request(
    widget.reply.id.toInt(),
    widget.reply.ctime.toInt(),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.resolver,
      builder: (context, _) {
        final floor = widget.resolver.floorOf(widget.reply.id.toInt());
        return AnimatedSize(
          duration: const Duration(milliseconds: 150),
          child: floor == null
              ? const SizedBox.shrink()
              : Text('#$floor', style: widget.style),
        );
      },
    );
  }
}
