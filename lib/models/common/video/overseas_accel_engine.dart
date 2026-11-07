/// Multi-thread download engines for viewers far from the mainland CDNs.
enum OverseasAccelEngine {
  /// From lemonteaau/PiliPlus (PiliPlus 海外加速版), an adaptation of
  /// Bilibili-thread-ripper: https://github.com/lemonteaau/PiliPlus
  ripper('线程撕裂者', 'lemonteaau/PiliPlus 海外加速版'),

  /// From nishuodedui1145-del/PiliPlus (PiliPlus-BTR), an independent Dart
  /// implementation after Bilibili-thread-ripper:
  /// https://github.com/nishuodedui1145-del/PiliPlus
  btr('BTR', 'nishuodedui1145-del/PiliPlus-BTR');

  const OverseasAccelEngine(this.label, this.source);

  final String label;
  final String source;
}
