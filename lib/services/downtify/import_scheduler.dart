import 'dart:async';

/// Deterministic clock and timer seam for Downtify import work.
///
/// Production uses the real clock and [Timer]; tests inject
/// [ManualImportScheduler] and advance its clock explicitly instead of
/// sleeping on wall-clock time.
abstract interface class ImportScheduler {
  DateTime now();

  /// Schedules [callback] after [delay]. The returned [Timer] cancels it.
  Timer schedule(Duration delay, Future<void> Function() callback);
}

class TimerImportScheduler implements ImportScheduler {
  @override
  DateTime now() => DateTime.now();

  @override
  Timer schedule(Duration delay, Future<void> Function() callback) =>
      Timer(delay, () {
        callback();
      });
}
