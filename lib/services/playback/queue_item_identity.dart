class QueueItemIdentity {
  QueueItemIdentity({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  int _counter = 0;

  String next() => '${_now().microsecondsSinceEpoch}-${_counter++}';
}
