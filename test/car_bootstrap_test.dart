import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/features/car/car_bootstrap.dart';
import 'package:spotifin/features/car/car_controller.dart';
import 'package:spotifin/features/car/car_template_coordinator.dart';
import 'package:spotifin/storage/database.dart';

/// Mounts [initCarListeners] once in `initState` and runs its cleanup on
/// dispose, mirroring the app bootstrap lifetime.
class _BootstrapHost extends ConsumerStatefulWidget {
  const _BootstrapHost({
    required this.renders,
    required this.carPlayEvents,
    required this.androidEvents,
    required this.unobserves,
  });

  final List<CarState> renders;
  final List<void Function()> carPlayEvents;
  final List<void Function()> androidEvents;
  final List<String> unobserves;

  @override
  ConsumerState<_BootstrapHost> createState() => _BootstrapHostState();
}

class _BootstrapHostState extends ConsumerState<_BootstrapHost> {
  void Function()? _cleanup;

  @override
  void initState() {
    super.initState();
    _cleanup = initCarListeners(
      ref,
      observeCarPlay: (notify) => widget.carPlayEvents.add(notify),
      observeAndroidAuto: (notify) => widget.androidEvents.add(notify),
      unobserveCarPlay: () => widget.unobserves.add('carplay'),
      unobserveAndroidAuto: () => widget.unobserves.add('android'),
      renderState: (state) async {
        widget.renders.add(state);
      },
    );
  }

  @override
  void dispose() {
    _cleanup?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('mount, dispose, and remount manage listeners once', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await tester.runAsync(database.close);
    });
    final renders = <CarState>[];
    final carPlayEvents = <void Function()>[];
    final androidEvents = <void Function()>[];
    final unobserves = <String>[];

    Widget host() => ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: MaterialApp(
        home: _BootstrapHost(
          renders: renders,
          carPlayEvents: carPlayEvents,
          androidEvents: androidEvents,
          unobserves: unobserves,
        ),
      ),
    );

    // Mount registers both native listeners without the outside-build
    // listener assertion.
    await tester.pumpWidget(host());
    expect(carPlayEvents, hasLength(1));
    expect(androidEvents, hasLength(1));
    expect(unobserves, isEmpty);

    // Native connection callbacks render while mounted.
    carPlayEvents.single();
    await tester.pump();
    expect(renders, hasLength(1));
    androidEvents.single();
    await tester.pump();
    expect(renders, hasLength(2));

    // Dispose removes both listeners exactly once.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(unobserves, ['carplay', 'android']);

    // Late native callbacks cannot use a disposed ref.
    final rendersAfterDispose = renders.length;
    carPlayEvents.single();
    androidEvents.single();
    await tester.pump();
    expect(renders.length, rendersAfterDispose);

    // Remount works again.
    await tester.pumpWidget(host());
    expect(carPlayEvents, hasLength(2));
    expect(androidEvents, hasLength(2));
    carPlayEvents.last();
    await tester.pump();
    expect(renders.length, rendersAfterDispose + 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(unobserves, ['carplay', 'android', 'carplay', 'android']);
  });

  group('CarTemplateCoordinator', () {
    CarState state(bool signedIn) => CarState(signedIn: signedIn);

    test('coalesces a slow render to the latest state', () async {
      final rendered = <CarState>[];
      final gate = Completer<void>();
      final coordinator = CarTemplateCoordinator(
        render: (update) async {
          if (rendered.isEmpty) await gate.future;
          rendered.add(update);
        },
      );
      addTearDown(() async {
        gate.isCompleted ? null : gate.complete();
        coordinator.dispose();
      });

      coordinator.update(state(true));
      await Future<void>.delayed(Duration.zero);
      coordinator.update(state(true));
      coordinator.update(state(false));
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // The slow first render ran, then only the latest pending state.
      expect(rendered.map((update) => update.signedIn), [true, false]);
    });

    test('sign-out while rendering still renders the sign-out state', () async {
      final rendered = <CarState>[];
      final gate = Completer<void>();
      final coordinator = CarTemplateCoordinator(
        render: (update) async {
          rendered.add(update);
          if (rendered.length == 1) await gate.future;
        },
      );
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        coordinator.dispose();
      });

      coordinator.update(state(true));
      await Future<void>.delayed(Duration.zero);
      coordinator.update(state(false));
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(rendered.last.signedIn, isFalse);
    });

    test('a failed render does not block later renders', () async {
      final rendered = <CarState>[];
      var failures = 1;
      final coordinator = CarTemplateCoordinator(
        render: (update) async {
          if (failures > 0) {
            failures--;
            throw StateError('render failed');
          }
          rendered.add(update);
        },
      );
      addTearDown(coordinator.dispose);

      coordinator.update(state(true));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      coordinator.update(state(false));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(rendered.map((update) => update.signedIn), [false]);
    });

    test('dispose stops future renders and callbacks', () async {
      final rendered = <CarState>[];
      final coordinator = CarTemplateCoordinator(
        render: (update) async {
          rendered.add(update);
        },
      );

      coordinator.update(state(true));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(rendered, hasLength(1));
      coordinator.dispose();
      coordinator.update(state(false));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(rendered, hasLength(1));
    });
  });
}
