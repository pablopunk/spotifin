import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/app_shortcuts.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('Down moves focus vertically instead of scrolling', (
    tester,
  ) async {
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await _pumpApp(
      tester,
      child: Column(
        children: [_focusableInkWell(first), _focusableInkWell(second)],
      ),
    );

    first.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);

    expect(second.hasPrimaryFocus, isTrue);
  });

  testWidgets('Right moves focus horizontally', (tester) async {
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await _pumpApp(
      tester,
      child: Row(
        children: [_focusableInkWell(first), _focusableInkWell(second)],
      ),
    );

    first.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);

    expect(second.hasPrimaryFocus, isTrue);
  });

  testWidgets('Enter activates the focused InkWell once', (tester) async {
    var activations = 0;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await _pumpApp(
      tester,
      child: _focusableInkWell(focusNode, onTap: () => activations++),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(activations, 1);
  });

  testWidgets('Space toggles playback without activating the focused InkWell', (
    tester,
  ) async {
    var activations = 0;
    var toggles = 0;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await _pumpApp(
      tester,
      onTogglePlayback: () => toggles++,
      child: _focusableInkWell(focusNode, onTap: () => activations++),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);

    expect(toggles, 1);
    expect(activations, 0);
  });

  testWidgets('TextField keeps caret arrows and Space text entry', (
    tester,
  ) async {
    var toggles = 0;
    final controller = TextEditingController(text: 'ab');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    controller.selection = const TextSelection.collapsed(offset: 1);
    await _pumpApp(
      tester,
      onTogglePlayback: () => toggles++,
      child: TextField(controller: controller, focusNode: focusNode),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(controller.selection.baseOffset, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: ' ab',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );

    expect(controller.text, ' ab');
    expect(toggles, 0);
  });

  testWidgets('Meta+K opens Search only on Apple platforms', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    var searches = 0;
    await _pumpApp(tester, onOpenSearch: () => searches++);

    await _sendChord(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.keyK,
    );
    expect(searches, 1);
    await _sendChord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyK,
    );
    expect(searches, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    testWidgets('Ctrl+K opens Search only on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      var searches = 0;
      await _pumpApp(tester, onOpenSearch: () => searches++);

      await _sendChord(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyK,
      );
      expect(searches, 1);
      await _sendChord(
        tester,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.keyK,
      );
      expect(searches, 1);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('primary arrows control tracks and plain arrows move focus', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var previous = 0;
    var next = 0;
    final left = FocusNode();
    final middle = FocusNode();
    final right = FocusNode();
    addTearDown(left.dispose);
    addTearDown(middle.dispose);
    addTearDown(right.dispose);
    await _pumpApp(
      tester,
      onPreviousTrack: () => previous++,
      onNextTrack: () => next++,
      child: Row(
        children: [
          _focusableInkWell(left),
          _focusableInkWell(middle),
          _focusableInkWell(right),
        ],
      ),
    );

    middle.requestFocus();
    await tester.pump();
    await _sendChord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.arrowLeft,
    );
    await _sendChord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.arrowRight,
    );
    expect((previous, next), (1, 1));
    expect(middle.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(left.hasPrimaryFocus, isTrue);
    expect((previous, next), (1, 1));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('app commands ignore KeyRepeatEvent', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var toggles = 0;
    var searches = 0;
    var previous = 0;
    var next = 0;
    await _pumpApp(
      tester,
      onTogglePlayback: () => toggles++,
      onOpenSearch: () => searches++,
      onPreviousTrack: () => previous++,
      onNextTrack: () => next++,
    );

    await _sendDownRepeatUp(tester, LogicalKeyboardKey.space);
    await _sendModifiedDownRepeatUp(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyK,
    );
    await _sendModifiedDownRepeatUp(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.arrowLeft,
    );
    await _sendModifiedDownRepeatUp(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.arrowRight,
    );

    expect((toggles, searches, previous, next), (1, 1, 1, 1));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('disabled shortcuts preserve default button Space activation', (
    tester,
  ) async {
    var activations = 0;
    var toggles = 0;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await _pumpApp(
      tester,
      enabled: false,
      onTogglePlayback: () => toggles++,
      child: FilledButton(
        focusNode: focusNode,
        onPressed: () => activations++,
        child: const Text('Log in'),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);

    expect(activations, 1);
    expect(toggles, 0);
  });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  bool enabled = true,
  VoidCallback? onTogglePlayback,
  VoidCallback? onOpenSearch,
  VoidCallback? onPreviousTrack,
  VoidCallback? onNextTrack,
  Widget child = const SizedBox(),
}) => tester.pumpWidget(
  MaterialApp(
    shortcuts: buildAppShortcuts(enabled: enabled),
    actions: buildAppActions(
      onTogglePlayback: onTogglePlayback ?? () {},
      onOpenSearch: onOpenSearch ?? () {},
      onPreviousTrack: onPreviousTrack ?? () {},
      onNextTrack: onNextTrack ?? () {},
    ),
    home: Scaffold(body: child),
  ),
);

Widget _focusableInkWell(FocusNode focusNode, {VoidCallback? onTap}) =>
    SizedBox(
      width: 80,
      height: 80,
      child: InkWell(focusNode: focusNode, onTap: onTap ?? () {}),
    );

Future<void> _sendChord(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
}

Future<void> _sendDownRepeatUp(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyRepeatEvent(key);
  await tester.sendKeyUpEvent(key);
}

Future<void> _sendModifiedDownRepeatUp(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await _sendDownRepeatUp(tester, key);
  await tester.sendKeyUpEvent(modifier);
}
