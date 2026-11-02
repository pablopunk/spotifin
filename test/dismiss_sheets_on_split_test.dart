import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/features/shell/dismiss_sheets_on_split.dart';

void main() {
  testWidgets('closing happens only when the screen starts to split', (
    tester,
  ) async {
    final split = ValueNotifier(false);
    addTearDown(split.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: split,
          builder: (_, value, _) => DismissSheetsOnSplit(
            split: value,
            child: Builder(
              builder: (inner) {
                context = inner;
                return const Scaffold(body: Text('home'));
              },
            ),
          ),
        ),
      ),
    );

    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SizedBox(height: 200, child: Text('now playing')),
    );
    await tester.pumpAndSettle();
    expect(find.text('now playing'), findsOneWidget);

    split.value = true;
    await tester.pumpAndSettle();

    expect(find.text('now playing'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('an already split screen leaves a later sheet alone', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: DismissSheetsOnSplit(
          split: true,
          child: Builder(
            builder: (inner) {
              context = inner;
              return const Scaffold(body: Text('home'));
            },
          ),
        ),
      ),
    );

    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SizedBox(height: 200, child: Text('now playing')),
    );
    await tester.pumpAndSettle();

    expect(find.text('now playing'), findsOneWidget);
  });
}
