String normalizeVersion(String value) =>
    value.trim().replaceFirst(RegExp(r'^v'), '');

int compareVersions(String a, String b) {
  final left = _segments(a);
  final right = _segments(b);
  for (var index = 0; index < left.length; index++) {
    final difference = left[index].compareTo(right[index]);
    if (difference != 0) return difference;
  }
  return 0;
}

bool isNewerVersion(String candidate, String current) =>
    compareVersions(candidate, current) > 0;

List<int> _segments(String value) {
  final parts = normalizeVersion(value).split('+').first.split('.');
  return List.generate(3, (index) {
    if (index >= parts.length) return 0;
    return int.tryParse(parts[index]) ?? 0;
  });
}
