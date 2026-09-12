final _secretPatterns = <RegExp>[
  RegExp(
    r'(api[_-]?key|token|authorization)\s*[=:]\s*"?[^&\s",]+',
    caseSensitive: false,
  ),
];

String redactSecrets(Object? error) => _secretPatterns.fold(
  error.toString(),
  (text, pattern) => text.replaceAll(pattern, '<redacted>'),
);
