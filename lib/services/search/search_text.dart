/// Shared search-text helpers: accent-insensitive, case-insensitive matching
/// that stays blazing fast.
///
/// The library search runs a single SQLite `LIKE` scan per query word, so the
/// normalization here must be mirrorable in SQL with plain `LOWER` + nested
/// `REPLACE` calls (no extensions, works on native and web). The Dart side
/// folds diacritics the same way, which keeps SQL recall and in-memory
/// filtering (car search, artist/album grouping) consistent.
///
/// Example: `Rosalia` matches `ROSALÍA` because both fold to `rosalia`.
library;

/// Accented/diacritic characters folded to their ASCII base.
///
/// Keys are lowercase; uppercase variants are derived with [String.toUpperCase]
/// for the SQL fold (SQLite's `LOWER` only folds ASCII, and `LIKE` is
/// ASCII-only case-insensitive, so both cases must be replaced explicitly).
const List<List<String>> _foldGroups = [
  ['a', 'àáâãäåāăąǎȁȃạảấầẩẫậắằẳẵặ'],
  ['c', 'çćĉċč'],
  ['d', 'ďđð'],
  ['e', 'èéêëēĕėęěẹẻẽếềểễệ'],
  ['g', 'ĝğġģ'],
  ['h', 'ĥħ'],
  ['i', 'ìíîïĩīĭįıǐịỉ'],
  ['j', 'ĵ'],
  ['k', 'ķĸ'],
  ['l', 'ĺļľŀł'],
  ['n', 'ñńņňŉ'],
  ['o', 'òóôõöøōŏőǒọỏốồổỗộớờởỡợ'],
  ['r', 'ŕŗř'],
  ['s', 'śŝşšș'],
  ['t', 'ţťŧț'],
  ['u', 'ùúûüũūŭůűųǔụủứừửữự'],
  ['w', 'ŵ'],
  ['y', 'ýÿŷỳỵỷỹ'],
  ['z', 'źżž'],
];

/// Expanding folds applied before the single-character groups above.
/// Lowercase-first: Dart's [String.toLowerCase] already maps Æ→æ, Œ→œ,
/// Þ→þ, ẞ→ß, so only lowercase keys are needed on the Dart side.
const Map<String, String> _expandingFolds = {
  'ß': 'ss',
  'æ': 'ae',
  'œ': 'oe',
  'þ': 'th',
};

/// Combining diacritical mark ranges stripped after case folding, so
/// decomposed (NFD) input matches precomposed text and vice versa.
bool _isCombiningMark(int rune) =>
    (rune >= 0x0300 && rune <= 0x036f) ||
    (rune >= 0x1ab0 && rune <= 0x1aff) ||
    (rune >= 0x1dc0 && rune <= 0x1dff) ||
    (rune >= 0x20d0 && rune <= 0x20ff) ||
    (rune >= 0xfe20 && rune <= 0xfe2f);

final Map<String, String> _singleFold = {
  for (final group in _foldGroups)
    for (final char in group[1].split('')) char: group[0],
};

/// Lowercases [input] and folds diacritics to ASCII.
///
/// Punctuation and spacing are preserved (whitespace is collapsed), so this
/// is suitable for display-adjacent comparisons. Use [compactSearchText] or
/// [splitSearchWords] when punctuation tolerance is needed.
String normalizeSearchText(String input) {
  var folded = input.toLowerCase();
  _expandingFolds.forEach((from, to) {
    folded = folded.replaceAll(from, to);
  });
  final buffer = StringBuffer();
  for (final rune in folded.runes) {
    if (_isCombiningMark(rune)) continue;
    final char = String.fromCharCode(rune);
    buffer.write(_singleFold[char] ?? char);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Normalizes [input] and removes everything but `a-z0-9`.
///
/// Both the indexed text and the query go through this shape before the SQL
/// `LIKE '%token%'` comparison, which makes matching punctuation-tolerant
/// (`dont` matches `Don't`) while keeping patterns `LIKE`-safe.
String compactSearchText(String input) =>
    normalizeSearchText(input).replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Normalizes a single raw query word into its `LIKE`-safe token form.
String normalizeSearchToken(String word) => compactSearchText(word);

/// Splits a raw query into normalized search tokens.
///
/// Splitting on non-alphanumerics (not just whitespace) makes
/// punctuation-joined queries behave: `rock&roll` searches for both `rock`
/// and `roll`. Lone single letters (usually punctuation debris like the `t`
/// in `don't`) are dropped when a longer token exists, since `LIKE '%t%'`
/// matches nearly everything and only adds noise. Single digits are kept:
/// `track 1` must not match `track 2`.
List<String> splitSearchWords(String query) {
  final words = normalizeSearchText(query)
      .split(RegExp(r'[^a-z0-9]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.any((word) => word.length > 1)) {
    return words
        .where((word) => word.length > 1 || _isSingleDigit(word))
        .toList();
  }
  return words;
}

bool _isSingleDigit(String word) =>
    word.length == 1 &&
    word.codeUnitAt(0) >= 0x30 &&
    word.codeUnitAt(0) <= 0x39;

/// Whether folded [haystack] contains every [token] as a substring.
///
/// Mirrors the SQL predicate (`AND` of `LIKE '%token%'`), so in-memory
/// filtering stays consistent with database search.
bool matchesAllTokens(String haystack, List<String> tokens) {
  if (tokens.isEmpty) return false;
  final compact = compactSearchText(haystack);
  return tokens.every(compact.contains);
}

/// Normalized word list of a field, for relevance scoring with typo tolerance.
List<String> searchFieldWords(String field) =>
    normalizeSearchText(field)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.isNotEmpty)
        .toList();

/// Capped edit distance: true when [a] and [b] differ by at most [max].
///
/// Early-exits on length difference and per-row minima, so it stays cheap
/// enough to run over a few thousand in-memory tracks per keystroke.
bool _withinEditDistance(String a, String b, int max) {
  if ((a.length - b.length).abs() > max) return false;
  if (a == b) return true;
  // Wagner-Fischer with two rows and early exit.
  var previous = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    var current = List<int>.filled(b.length + 1, 0);
    current[0] = i;
    var rowMin = current[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var best = previous[j] + 1; // deletion
      final insertion = current[j - 1] + 1;
      if (insertion < best) best = insertion;
      final substitution = previous[j - 1] + cost;
      if (substitution < best) best = substitution;
      current[j] = best;
      if (best < rowMin) rowMin = best;
    }
    if (rowMin > max) return false;
    previous = current;
  }
  return previous[b.length] <= max;
}

int _wordQuality(String word, String token) {
  if (word == token) return 16;
  if (word.startsWith(token)) return 8;
  if (word.contains(token)) return 4;
  // Typo tolerance, guarded: same first letter avoids the classic
  // fuzzy-search soup of unrelated matches.
  if (token.length >= 4 &&
      word.length >= 3 &&
      word[0] == token[0] &&
      _withinEditDistance(word, token, token.length <= 5 ? 1 : 2)) {
    return 2;
  }
  return 0;
}

/// Relevance score for a track against normalized [tokens].
///
/// Zero means "no match" (some token matches nothing: `AND` semantics, just
/// like the SQL query). Otherwise higher is better; field weights prefer
/// title > artist > album. Pure-Dart and allocation-light for the hot path.
int scoreTrackForSearch({
  required String name,
  required String artist,
  required String album,
  required List<String> tokens,
}) {
  if (tokens.isEmpty) return 0;
  const weights = [3, 2, 1];
  final fields = [
    searchFieldWords(name),
    searchFieldWords(artist),
    searchFieldWords(album),
  ];
  var total = 0;
  for (final token in tokens) {
    var best = 0;
    for (var i = 0; i < fields.length; i++) {
      for (final word in fields[i]) {
        final quality = _wordQuality(word, token);
        if (quality == 0) continue;
        final weighted = quality * weights[i];
        if (weighted > best) best = weighted;
      }
    }
    if (best == 0) return 0;
    total += best;
  }
  return total;
}

/// Punctuation and spacing stripped (mapped to '') by the SQLite fold so the
/// SQL haystack matches [compactSearchText] for realistic metadata.
///
/// Keep this limited to characters that plausibly appear in music metadata;
/// exotic leftovers simply fall back to exact matching in SQL while the
/// pure-Dart matcher (which strips everything but `a-z0-9`) stays broader.
const String sqlStripChars =
    ' \t\'’‘"“”—–-_.,;:!?()[]{}&+/\\|@#\$%*=<>~^·•°…«»¡¿';

/// Ordered `(from, '')` pairs applied after [sqlFoldReplacements].
List<MapEntry<String, String>> get sqlStripReplacements => [
  for (final char in sqlStripChars.split('')) MapEntry(char, ''),
];

/// Ordered `(from, to)` pairs for the SQLite accent fold.
///
/// Applied as nested `REPLACE(LOWER(column), from, to)` calls. Includes
/// uppercase variants explicitly because SQLite's `LOWER`/`LIKE` only handle
/// ASCII case. Excludes expanding folds whose uppercase form is multi-char
/// (handled separately below); pure-Dart callers should prefer
/// [normalizeSearchText], this exists only for the drift query builder.
List<MapEntry<String, String>> get sqlFoldReplacements {
  final replacements = <MapEntry<String, String>>[];
  final seen = <String>{};
  void add(String from, String to) {
    if (seen.add(from)) replacements.add(MapEntry(from, to));
  }

  for (final group in _foldGroups) {
    for (final char in group[1].split('')) {
      add(char, group[0]);
      final upper = char.toUpperCase();
      if (upper.length == 1 && upper != char) add(upper, group[0]);
    }
  }
  _expandingFolds.forEach((from, to) {
    add(from, to);
    final upper = from.toUpperCase();
    if (upper != from) add(upper, to);
  });
  // Forms Dart's toLowerCase produces that SQLite's LOWER never will.
  add('İ', 'i'); // U+0130 → i + combining dot → i
  add('ẞ', 'ss'); // U+1E9E capital sharp s
  return replacements;
}
