import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/search/search_text.dart';

void main() {
  test('folds accents and case: Rosalia matches ROSALÍA', () {
    expect(normalizeSearchText('ROSALÍA'), 'rosalia');
    expect(normalizeSearchText('Rosalia'), 'rosalia');
    expect(normalizeSearchText('rosalía'), 'rosalia');
    expect(compactSearchText('ROSALÍA'), 'rosalia');
  });

  test('folds a range of Latin diacritics', () {
    expect(normalizeSearchText('Beyoncé'), 'beyonce');
    expect(normalizeSearchText('MÖTLEY CRÜE'), 'motley crue');
    expect(normalizeSearchText('Sinéad O’Connor'), 'sinead o’connor');
    expect(normalizeSearchText('Björk'), 'bjork');
    expect(normalizeSearchText('Sigur Rós'), 'sigur ros');
    expect(normalizeSearchText('Zoë'), 'zoe');
    expect(normalizeSearchText('François'), 'francois');
    expect(normalizeSearchText('Łódź'), 'lodz');
    expect(normalizeSearchText('Æther'), 'aether');
    expect(normalizeSearchText('Straße'), 'strasse');
  });

  test('strips combining marks from decomposed input', () {
    // e + U+0301 (combining acute) must match precomposed é.
    expect(normalizeSearchText('é'), 'e');
    expect(normalizeSearchText('Rosalía'), 'rosalia');
  });

  test('splits queries into LIKE-safe tokens', () {
    expect(splitSearchWords('  Rosalía!! '), ['rosalia']);
    expect(splitSearchWords('rock&roll'), ['rock', 'roll']);
    expect(splitSearchWords('Box Car Racer'), ['box', 'car', 'racer']);
    // Punctuation debris is dropped when a longer token exists.
    expect(splitSearchWords("don't"), ['don']);
    // Single digits are meaningful and kept.
    expect(splitSearchWords('Track 1'), ['track', '1']);
    expect(splitSearchWords(''), isEmpty);
    expect(splitSearchWords('  '), isEmpty);
  });

  test('matchesAllTokens is punctuation tolerant', () {
    expect(matchesAllTokens("Don't Stop", ['don']), isTrue);
    expect(matchesAllTokens('ROSALÍA', ['rosalia']), isTrue);
    expect(matchesAllTokens('Tiny Voices', ['tiny', 'racer']), isFalse);
    expect(matchesAllTokens('Box Car Racer', ['tiny', 'racer']), isFalse);
    expect(matchesAllTokens('Anything', []), isFalse);
  });

  test('scores exact matches above typos above misses', () {
    score(
      String name, {
      String artist = '',
      String album = '',
      required String query,
    }) => scoreTrackForSearch(
      name: name,
      artist: artist,
      album: album,
      tokens: splitSearchWords(query),
    );

    final exact = score('Rosalia', artist: 'ROSALÍA', query: 'rosalia');
    final typo = score('Rosaila', query: 'rosalia');
    expect(exact, greaterThan(0));
    expect(typo, greaterThan(0));
    expect(exact, greaterThan(typo));
    expect(score('Metallica', query: 'rosalia'), 0);
    expect(score('Anything', query: ''), 0);
    // Every token must match somewhere (AND semantics).
    expect(score('Tiny Voices', artist: 'Someone', query: 'tiny racer'), 0);
    expect(
      score('Tiny Voices', artist: 'Box Car Racer', query: 'tiny racer'),
      greaterThan(0),
    );
  });

  test('SQL fold covers both cases of accented letters', () {
    final folds = Map.fromEntries(sqlFoldReplacements);
    expect(folds['í'], 'i');
    expect(folds['Í'], 'i');
    expect(folds['á'], 'a');
    expect(folds['Á'], 'a');
    expect(folds['ß'], 'ss');
    expect(folds['æ'], 'ae');
    // Every replacement target is plain ASCII.
    for (final entry in sqlFoldReplacements) {
      expect(entry.value.codeUnits.every((c) => c < 128), isTrue);
    }
  });
}
