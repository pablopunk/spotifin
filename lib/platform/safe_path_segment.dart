String safePathSegment(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  if (sanitized == '.' || sanitized == '..') return '_';
  return sanitized.isEmpty ? '_' : sanitized;
}
