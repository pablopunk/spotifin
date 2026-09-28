import '../downtify/downtify_models.dart';

/// Saved import statuses recognized by the controller and widgets.
enum ImportStatus {
  submitting,
  retrying,
  queued,
  downloading,
  requestingScan,
  waitingForJellyfin,
  scanDenied,
  imported,
  downloadFailed,
  importTimedOut,
  unknown,
}

/// A persisted status string parsed into a typed value.
///
/// Unknown strings retain their raw value, stay inert (no automatic
/// effects), and keep their row visible.
class ParsedImportStatus {
  const ParsedImportStatus(this.kind, this.raw);

  final ImportStatus kind;
  final String raw;
}

ParsedImportStatus parseImportStatus(String raw) {
  final kind = switch (raw) {
    'submitting' => ImportStatus.submitting,
    'retrying' => ImportStatus.retrying,
    'queued' => ImportStatus.queued,
    'downloading' => ImportStatus.downloading,
    'requestingScan' => ImportStatus.requestingScan,
    'waitingForJellyfin' => ImportStatus.waitingForJellyfin,
    'scanDenied' => ImportStatus.scanDenied,
    'imported' => ImportStatus.imported,
    'downloadFailed' => ImportStatus.downloadFailed,
    'importTimedOut' => ImportStatus.importTimedOut,
    _ => ImportStatus.unknown,
  };
  return ParsedImportStatus(kind, raw);
}

/// Nonterminal statuses with automatic effects (spinner/progress display).
bool isImportActive(ParsedImportStatus status) => switch (status.kind) {
  ImportStatus.submitting ||
  ImportStatus.retrying ||
  ImportStatus.queued ||
  ImportStatus.downloading ||
  ImportStatus.requestingScan ||
  ImportStatus.waitingForJellyfin ||
  ImportStatus.scanDenied => true,
  ImportStatus.imported ||
  ImportStatus.downloadFailed ||
  ImportStatus.importTimedOut ||
  ImportStatus.unknown => false,
};

/// Rows shown in the download-queue section with remote removal.
bool isDownloadQueueRow(ParsedImportStatus status) => switch (status.kind) {
  ImportStatus.submitting ||
  ImportStatus.retrying ||
  ImportStatus.queued ||
  ImportStatus.downloading ||
  ImportStatus.downloadFailed => true,
  _ => false,
};

bool isTerminalImport(ParsedImportStatus status) => switch (status.kind) {
  ImportStatus.imported ||
  ImportStatus.downloadFailed ||
  ImportStatus.importTimedOut => true,
  _ => false,
};

/// Manual retry is exposed for both terminal errors.
bool canRetryImport(ParsedImportStatus status) => switch (status.kind) {
  ImportStatus.downloadFailed || ImportStatus.importTimedOut => true,
  _ => false,
};

/// Only download-queue rows expose remote removal.
bool canRemoveImportRemotely(ParsedImportStatus status) =>
    isDownloadQueueRow(status);

/// Only imported rows expose local dismissal.
bool canDismissImportLocally(ParsedImportStatus status) =>
    status.kind == ImportStatus.imported;

/// Finds the queue job confirming a saved row.
///
/// Queue data identifies jobs by `job.song.id`: the stored job id is tried
/// first, then the external song id. Jobs never match across origins; the
/// caller only passes jobs read from the row's own origin.
DowntifyJob? matchImportJob(
  List<DowntifyJob> jobs, {
  required String? storedJobId,
  required String externalSongId,
}) {
  if (storedJobId != null && storedJobId.isNotEmpty) {
    for (final job in jobs) {
      if (job.song.id == storedJobId) return job;
    }
  }
  for (final job in jobs) {
    if (job.song.id == externalSongId) return job;
  }
  return null;
}

/// Recovery decision for one saved row against a confirmed queue read.
enum ImportRecoveryKind {
  /// Keep polling; progress, completion, and automatic retries apply.
  resumePolling,

  /// Adopt the confirmed queued/downloading job.
  confirmRemote,

  /// Request a scan batch for a confirmed done job.
  requestScan,

  /// Schedule one scan batch without needing a remote job.
  scheduleScanBatch,

  /// Resume catalog checks without downloading or rescanning.
  resumeCatalog,

  /// Preserve terminal outcomes untouched.
  preserveTerminal,

  /// No usable confirmation: mark interrupted, manual retry required.
  markInterrupted,

  /// Unknown persisted strings stay inert with their raw value.
  inert,
}

class ImportRecovery {
  const ImportRecovery(this.kind, {this.job, this.message});

  final ImportRecoveryKind kind;
  final DowntifyJob? job;
  final String? message;
}

/// Decides recovery for [saved] given [jobs] from a successful queue read.
///
/// Interrupted submissions are never blindly POSTed again: without a
/// usable confirmation the row becomes a terminal failure for manual
/// retry instead.
ImportRecovery decideImportRecovery({
  required ParsedImportStatus saved,
  required List<DowntifyJob> jobs,
  required String? storedJobId,
  required String externalSongId,
}) {
  switch (saved.kind) {
    case ImportStatus.imported:
    case ImportStatus.downloadFailed:
    case ImportStatus.importTimedOut:
      return const ImportRecovery(ImportRecoveryKind.preserveTerminal);
    case ImportStatus.unknown:
      return const ImportRecovery(ImportRecoveryKind.inert);
    case ImportStatus.submitting:
    case ImportStatus.retrying:
      final job = matchImportJob(
        jobs,
        storedJobId: storedJobId,
        externalSongId: externalSongId,
      );
      if (job == null || job.status == DowntifyJobStatus.unknown) {
        return const ImportRecovery(
          ImportRecoveryKind.markInterrupted,
          message:
              'Download interrupted before the server confirmed it. '
              'Retry manually to try again.',
        );
      }
      if (job.status == DowntifyJobStatus.done) {
        return ImportRecovery(ImportRecoveryKind.requestScan, job: job);
      }
      if (job.status == DowntifyJobStatus.error) {
        // A confirmed failure still flows through the automatic retry
        // policy rather than an immediate terminal mark.
        return ImportRecovery(ImportRecoveryKind.confirmRemote, job: job);
      }
      return ImportRecovery(ImportRecoveryKind.confirmRemote, job: job);
    case ImportStatus.queued:
    case ImportStatus.downloading:
      return const ImportRecovery(ImportRecoveryKind.resumePolling);
    case ImportStatus.requestingScan:
      return const ImportRecovery(ImportRecoveryKind.scheduleScanBatch);
    case ImportStatus.waitingForJellyfin:
    case ImportStatus.scanDenied:
      return const ImportRecovery(ImportRecoveryKind.resumeCatalog);
  }
}

/// Strictly more than 15 minutes after [createdAt], evaluated only after a
/// successful catalog check with no match.
bool isImportTimedOut({required DateTime createdAt, required DateTime now}) =>
    now.difference(createdAt) > const Duration(minutes: 15);
