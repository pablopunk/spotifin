import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/features/car/car_bootstrap.dart';
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

  final List<WidgetRef> renders;
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
      renderTemplates: (renderRef) async {
        widget.renders.add(renderRef);
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
    final renders = <WidgetRef>[];
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
}
