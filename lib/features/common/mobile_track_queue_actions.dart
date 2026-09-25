import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';

final _openTrackActionsProvider = NotifierProvider<_OpenTrackActions, Object?>(
  _OpenTrackActions.new,
);

class _OpenTrackActions extends Notifier<Object?> {
  @override
  Object? build() => null;

  void set(Object? owner) => state = owner;
}

class MobileTrackQueueActions extends ConsumerStatefulWidget {
  const MobileTrackQueueActions({
    required this.track,
    required this.child,
    super.key,
  });

  final Track track;
  final Widget child;

  @override
  ConsumerState<MobileTrackQueueActions> createState() =>
      _MobileTrackQueueActionsState();
}

class _MobileTrackQueueActionsState
    extends ConsumerState<MobileTrackQueueActions> {
  static const _actionWidth = 80.0;
  static const _openWidth = _actionWidth * 2;

  final _owner = Object();
  double _offset = 0;
  bool _dragging = false;

  @override
  void didUpdateWidget(MobileTrackQueueActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _offset = 0;
      _dragging = false;
    }
  }

  void _close() {
    _offset = 0;
    _dragging = false;
    if (ref.read(_openTrackActionsProvider) == _owner) {
      ref.read(_openTrackActionsProvider.notifier).set(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(_openTrackActionsProvider, (previous, owner) {
      if (owner != _owner && _offset != 0) setState(_close);
    });
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _action(
                    icon: Icons.queue_play_next_rounded,
                    label: 'Play next',
                    onTap: () => ref.read(playbackProvider).addNextToQueue([
                      widget.track,
                    ]),
                  ),
                  _action(
                    icon: Icons.playlist_add_rounded,
                    label: 'Add to queue',
                    onTap: () =>
                        ref.read(playbackProvider).addToQueue(widget.track),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onHorizontalDragStart: (_) {
              setState(() => _dragging = true);
            },
            onHorizontalDragUpdate: (details) {
              setState(() {
                _offset = (_offset + details.primaryDelta!).clamp(
                  0,
                  _openWidth,
                );
              });
              if (_offset > 0 &&
                  ref.read(_openTrackActionsProvider) != _owner) {
                ref.read(_openTrackActionsProvider.notifier).set(_owner);
              }
            },
            onHorizontalDragEnd: (_) => setState(_settle),
            onHorizontalDragCancel: () => setState(_settle),
            child: AnimatedContainer(
              duration: _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              transform: Matrix4.translationValues(_offset, 0, 0),
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _settle() {
    _dragging = false;
    if (_offset >= _openWidth / 2) {
      _offset = _openWidth;
    } else {
      _close();
    }
  }

  Widget _action({
    required IconData icon,
    required String label,
    required Future<void> Function() onTap,
  }) => Material(
    color: SpotifinColors.interactive,
    child: InkWell(
      onTap: () async {
        setState(_close);
        await onTap();
      },
      child: SizedBox(
        width: _actionWidth,
        height: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: SpotifinColors.accent),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(fontSize: 10, color: SpotifinColors.text),
            ),
          ],
        ),
      ),
    ),
  );
}
