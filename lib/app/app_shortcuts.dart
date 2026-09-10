import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Map<ShortcutActivator, Intent> buildAppShortcuts({required bool enabled}) {
  final shortcuts = <ShortcutActivator, Intent>{...WidgetsApp.defaultShortcuts};
  if (!enabled) return shortcuts;

  _replaceShortcut(
    shortcuts,
    LogicalKeyboardKey.arrowUp,
    const DirectionalFocusIntent(TraversalDirection.up),
  );
  _replaceShortcut(
    shortcuts,
    LogicalKeyboardKey.arrowDown,
    const DirectionalFocusIntent(TraversalDirection.down),
  );
  _replaceShortcut(
    shortcuts,
    LogicalKeyboardKey.arrowLeft,
    const DirectionalFocusIntent(TraversalDirection.left),
  );
  _replaceShortcut(
    shortcuts,
    LogicalKeyboardKey.arrowRight,
    const DirectionalFocusIntent(TraversalDirection.right),
  );
  _replaceShortcut(shortcuts, LogicalKeyboardKey.enter, const ActivateIntent());
  _replaceShortcut(
    shortcuts,
    LogicalKeyboardKey.numpadEnter,
    const ActivateIntent(),
  );
  _replaceShortcut(
    shortcuts,
    LogicalKeyboardKey.space,
    const _TogglePlaybackIntent(),
  );

  final useMeta = _usesMetaAsPrimaryModifier;
  _replaceShortcut(
    shortcuts,
    LogicalKeyboardKey.keyK,
    const _OpenSearchIntent(),
    meta: useMeta,
    control: !useMeta,
  );
  _replaceShortcut(
    shortcuts,
    LogicalKeyboardKey.arrowLeft,
    const _PreviousTrackIntent(),
    meta: useMeta,
    control: !useMeta,
  );
  _replaceShortcut(
    shortcuts,
    LogicalKeyboardKey.arrowRight,
    const _NextTrackIntent(),
    meta: useMeta,
    control: !useMeta,
  );
  return shortcuts;
}

Map<Type, Action<Intent>> buildAppActions({
  required VoidCallback onTogglePlayback,
  required VoidCallback onOpenSearch,
  required VoidCallback onPreviousTrack,
  required VoidCallback onNextTrack,
}) => <Type, Action<Intent>>{
  ...WidgetsApp.defaultActions,
  _TogglePlaybackIntent: CallbackAction<_TogglePlaybackIntent>(
    onInvoke: (_) => onTogglePlayback(),
  ),
  _OpenSearchIntent: CallbackAction<_OpenSearchIntent>(
    onInvoke: (_) => onOpenSearch(),
  ),
  _PreviousTrackIntent: CallbackAction<_PreviousTrackIntent>(
    onInvoke: (_) => onPreviousTrack(),
  ),
  _NextTrackIntent: CallbackAction<_NextTrackIntent>(
    onInvoke: (_) => onNextTrack(),
  ),
};

void _replaceShortcut(
  Map<ShortcutActivator, Intent> shortcuts,
  LogicalKeyboardKey key,
  Intent intent, {
  bool meta = false,
  bool control = false,
}) {
  shortcuts.removeWhere(
    (activator, _) =>
        activator is SingleActivator &&
        activator.trigger == key &&
        activator.meta == meta &&
        activator.control == control &&
        !activator.shift &&
        !activator.alt,
  );
  shortcuts[SingleActivator(
        key,
        meta: meta,
        control: control,
        includeRepeats: false,
      )] =
      intent;
}

bool get _usesMetaAsPrimaryModifier => switch (defaultTargetPlatform) {
  TargetPlatform.iOS || TargetPlatform.macOS => true,
  _ => false,
};

class _TogglePlaybackIntent extends Intent {
  const _TogglePlaybackIntent();
}

class _OpenSearchIntent extends Intent {
  const _OpenSearchIntent();
}

class _PreviousTrackIntent extends Intent {
  const _PreviousTrackIntent();
}

class _NextTrackIntent extends Intent {
  const _NextTrackIntent();
}
