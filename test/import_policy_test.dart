import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/downtify/downtify_models.dart';
import 'package:spotifin/services/downtify/import_policy.dart';

DowntifyJob _job(String songId, DowntifyJobStatus status) => DowntifyJob(
  song: DowntifySong.fromJson({
    'song_id': songId,
    'name': 'Song $songId',
    'artists': ['Artist'],
  }),
  status: status,
  progress: 0,
  message: '',
  filename: null,
);

void main() {
  group('status parsing and predicates', () {
    test('recognizes all ten statuses plus unknown', () async {
      const known = {
        'submitting': ImportStatus.submitting,
        'retrying': ImportStatus.retrying,
        'queued': ImportStatus.queued,
        'downloading': ImportStatus.downloading,
        'requestingScan': ImportStatus.requestingScan,
        'waitingForJellyfin': ImportStatus.waitingForJellyfin,
        'scanDenied': ImportStatus.scanDenied,
        'imported': ImportStatus.imported,
        'downloadFailed': ImportStatus.downloadFailed,
        'importTimedOut': ImportStatus.importTimedOut,
      };
      for (final entry in known.entries) {
        final parsed = parseImportStatus(entry.key);
        expect(parsed.kind, entry.value);
        expect(parsed.raw, entry.key);
      }
      final unknown = parseImportStatus('mystery-v2');
      expect(unknown.kind, ImportStatus.unknown);
      expect(unknown.raw, 'mystery-v2');
    });

    test('retrying renders active and terminals offer retry', () async {
      expect(isImportActive(parseImportStatus('retrying')), isTrue);
      expect(isImportActive(parseImportStatus('requestingScan')), isTrue);
      expect(isImportActive(parseImportStatus('downloadFailed')), isFalse);
      expect(canRetryImport(parseImportStatus('downloadFailed')), isTrue);
      expect(canRetryImport(parseImportStatus('importTimedOut')), isTrue);
      expect(canRetryImport(parseImportStatus('queued')), isFalse);
      expect(canRemoveImportRemotely(parseImportStatus('queued')), isTrue);
      expect(
        canRemoveImportRemotely(parseImportStatus('waitingForJellyfin')),
        isFalse,
      );
      expect(canDismissImportLocally(parseImportStatus('imported')), isTrue);
      expect(
        canDismissImportLocally(parseImportStatus('downloadFailed')),
        isFalse,
      );
    });

    test('unknown rows are inert', () async {
      final parsed = parseImportStatus('future-status');
      expect(isImportActive(parsed), isFalse);
      expect(isTerminalImport(parsed), isFalse);
      expect(canRetryImport(parsed), isFalse);
      expect(canRemoveImportRemotely(parsed), isFalse);
      expect(canDismissImportLocally(parsed), isFalse);
    });
  });

  group('job matching', () {
    final jobs = [
      _job('song-a', DowntifyJobStatus.downloading),
      _job('song-b', DowntifyJobStatus.done),
    ];

    test('tries the stored job id before the external song id', () async {
      expect(
        matchImportJob(
          jobs,
          storedJobId: 'song-b',
          externalSongId: 'song-a',
        )?.song.id,
        'song-b',
      );
      expect(
        matchImportJob(
          jobs,
          storedJobId: null,
          externalSongId: 'song-a',
        )?.song.id,
        'song-a',
      );
      expect(
        matchImportJob(
          jobs,
          storedJobId: 'missing',
          externalSongId: 'song-a',
        )?.song.id,
        'song-a',
      );
      expect(
        matchImportJob(jobs, storedJobId: 'missing', externalSongId: 'absent'),
        isNull,
      );
    });
  });

  group('recovery decisions', () {
    ImportRecovery decide(
      String saved,
      List<DowntifyJob> jobs, {
      String? storedJobId,
      String externalSongId = 'song',
    }) => decideImportRecovery(
      saved: parseImportStatus(saved),
      jobs: jobs,
      storedJobId: storedJobId,
      externalSongId: externalSongId,
    );

    test('interrupted submissions never resubmit blindly', () async {
      final recovery = decide('submitting', [
        _job('other', DowntifyJobStatus.queued),
      ], externalSongId: 'song');
      expect(recovery.kind, ImportRecoveryKind.markInterrupted);
      expect(recovery.message, contains('manually'));
    });

    test('confirmed jobs are adopted or scanned', () async {
      expect(
        decide('submitting', [
          _job('song', DowntifyJobStatus.downloading),
        ], externalSongId: 'song').kind,
        ImportRecoveryKind.confirmRemote,
      );
      expect(
        decide('retrying', [
          _job('song', DowntifyJobStatus.done),
        ], externalSongId: 'song').kind,
        ImportRecoveryKind.requestScan,
      );
      expect(
        decide('submitting', [
          _job('song', DowntifyJobStatus.unknown),
        ], externalSongId: 'song').kind,
        ImportRecoveryKind.markInterrupted,
      );
    });

    test('queued rows resume without resubmission', () async {
      expect(
        decide('queued', const [], externalSongId: 'song').kind,
        ImportRecoveryKind.resumePolling,
      );
      expect(
        decide('downloading', [
          _job('other', DowntifyJobStatus.error),
        ], externalSongId: 'song').kind,
        ImportRecoveryKind.resumePolling,
      );
    });

    test('scan and catalog states resume their own work', () async {
      expect(
        decide('requestingScan', const [], externalSongId: 'song').kind,
        ImportRecoveryKind.scheduleScanBatch,
      );
      expect(
        decide('waitingForJellyfin', const [], externalSongId: 'song').kind,
        ImportRecoveryKind.resumeCatalog,
      );
      expect(
        decide('scanDenied', const [], externalSongId: 'song').kind,
        ImportRecoveryKind.resumeCatalog,
      );
    });

    test('terminal and unknown states are preserved inertly', () async {
      for (final status in ['imported', 'downloadFailed', 'importTimedOut']) {
        expect(
          decide(status, [
            _job('song', DowntifyJobStatus.error),
          ], externalSongId: 'song').kind,
          ImportRecoveryKind.preserveTerminal,
        );
      }
      expect(
        decide('mystery', [
          _job('song', DowntifyJobStatus.done),
        ], externalSongId: 'song').kind,
        ImportRecoveryKind.inert,
      );
    });
  });

  group('import timeout', () {
    test('is strictly more than fifteen minutes', () async {
      final createdAt = DateTime(2026, 1, 1, 12);
      expect(
        isImportTimedOut(
          createdAt: createdAt,
          now: createdAt.add(const Duration(minutes: 15)),
        ),
        isFalse,
      );
      expect(
        isImportTimedOut(
          createdAt: createdAt,
          now: createdAt.add(const Duration(minutes: 15, seconds: 1)),
        ),
        isTrue,
      );
    });
  });
}
