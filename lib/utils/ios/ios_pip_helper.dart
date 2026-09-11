import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class IosPipHelper {
  IosPipHelper._() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static final instance = IosPipHelper._();
  static const _channel = MethodChannel('com.piliplus/picture_in_picture');

  Future<bool> Function(String videoUrl)? onWillStart;
  Future<void> Function(Duration position, bool shouldResume)? onStopped;

  Future<bool> get isAvailable async {
    if (!Platform.isIOS) return false;
    return await _channel.invokeMethod<bool>('isAvailable') ?? false;
  }

  Future<void> start({
    required String videoUrl,
    String? audioUrl,
    required Duration position,
    required bool isPlaying,
  }) async {
    if (!Platform.isIOS) return;
    await _channel.invokeMethod<void>('start', {
      'videoUrl': videoUrl,
      'audioUrl': audioUrl,
      'positionMs': position.inMilliseconds,
      'isPlaying': isPlaying,
    });
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    final args = Map<String, dynamic>.from(call.arguments as Map);
    switch (call.method) {
      case 'willStart':
        return await onWillStart?.call(args['videoUrl'] as String) ?? false;
      case 'didStop':
        await onStopped?.call(
          Duration(milliseconds: (args['positionMs'] as num).round()),
          args['shouldResume'] as bool? ?? false,
        );
    }
  }
}
