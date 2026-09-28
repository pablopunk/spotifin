import 'dart:async';

import 'package:spotifin/services/downtify/import_scheduler.dart';

/// Manual [ImportScheduler] for tests: timers fire only when the test
/// advances the clock, and every due callback is awaited. No wall-clock
/// sleeps are needed.
class ManualImportScheduler implements ImportScheduler {
  ManualImportScheduler([DateTime? start])
    : _now = start ?? DateTime(2026, 1, 1);

  DateTime _now;
  final List<_ScheduledTask> _tasks = [];

  @override
  DateTime now() => _now;

  @override
  Timer schedule(Duration delay, Future<void> Function() callback) {
    final task = _ScheduledTask(this, _now.add(delay), callback);
    _tasks.add(task);
    return task;
  }

  int get pendingCount => _tasks.where((task) => task.isActive).length;

  void _remove(_ScheduledTask task) {
    _tasks.remove(task);
  }

  /// Advances the clock by [duration], awaiting every callback that becomes
  /// due in chronological order.
  Future<void> advance(Duration duration) async {
    final target = _now.add(duration);
    while (true) {
      _ScheduledTask? next;
      for (final task in _tasks) {
        if (!task.isActive) continue;
        if (task.due.isAfter(target)) continue;
        if (next == null || task.due.isBefore(next.due)) next = task;
      }
      if (next == null) break;
      _remove(next);
      _now = next.due;
      next._complete();
      await next.callback();
    }
    _now = target;
  }

  /// Runs every callback currently due without advancing the clock.
  Future<void> runDue() async {
    while (true) {
      _ScheduledTask? next;
      for (final task in _tasks) {
        if (!task.isActive) continue;
        if (task.due.isAfter(_now)) continue;
        if (next == null || task.due.isBefore(next.due)) next = task;
      }
      if (next == null) break;
      _remove(next);
      next._complete();
      await next.callback();
    }
  }
}

class _ScheduledTask implements Timer {
  _ScheduledTask(this._scheduler, this.due, this.callback);

  final ManualImportScheduler _scheduler;
  final DateTime due;
  final Future<void> Function() callback;
  bool _cancelled = false;
  bool _done = false;

  @override
  bool get isActive => !_cancelled && !_done;

  @override
  int get tick => 0;

  @override
  void cancel() {
    _cancelled = true;
    _scheduler._remove(this);
  }

  void _complete() {
    _done = true;
  }
}
