import 'dart:async';

import 'car_controller.dart';

/// Serializes and coalesces native car template renders.
///
/// At most one render is in flight; when it completes, the latest pending
/// state renders next — including a sign-out state — so an older completion
/// never overwrites a newer final template. A failed render never blocks
/// later renders. Disposal stops future renders and callbacks. Platform
/// adapters keep owning their own templates; this module only owns when to
/// render.
class CarTemplateCoordinator {
  CarTemplateCoordinator({
    required Future<void> Function(CarState state) render,
    void Function(Object error)? onError,
  }) : _render = render,
       _onError = onError;

  final Future<void> Function(CarState state) _render;
  final void Function(Object error)? _onError;

  CarState? _latest;
  bool _rendering = false;
  bool _disposed = false;

  /// Queues [state] for rendering, coalescing multiple updates to the
  /// latest while a render is in flight.
  void update(CarState state) {
    if (_disposed) return;
    _latest = state;
    _kick();
  }

  void _kick() {
    if (_rendering || _disposed) return;
    final state = _latest;
    if (state == null) return;
    _latest = null;
    _rendering = true;
    _render(state).then(
      (_) {
        _rendering = false;
        if (_disposed) return;
        if (_latest != null) {
          _kick();
        }
      },
      onError: (Object error) {
        _rendering = false;
        if (_disposed) return;
        try {
          _onError?.call(error);
        } catch (_) {}
        if (_latest != null) {
          _kick();
        }
      },
    );
  }

  void dispose() {
    _disposed = true;
    _latest = null;
  }
}
