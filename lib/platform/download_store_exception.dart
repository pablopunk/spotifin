class DownloadStoreException implements Exception {
  const DownloadStoreException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isRetryable =>
      statusCode == null ||
      statusCode == 408 ||
      statusCode == 429 ||
      statusCode! >= 500;

  @override
  String toString() => message;
}
