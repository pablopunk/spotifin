import 'version_comparison.dart';

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.name,
    required this.url,
    required this.publishedAt,
  });

  factory ReleaseInfo.fromGitHub(Map<String, dynamic> json) {
    final tag = json['tag_name'];
    if (tag is! String || normalizeVersion(tag).isEmpty) {
      throw const FormatException('Release tag is missing');
    }
    final url = json['html_url'];
    if (url is! String || url.isEmpty) {
      throw const FormatException('Release URL is missing');
    }
    final version = normalizeVersion(tag);
    final title = (json['name'] as String?)?.trim();
    final publishedAt = json['published_at'];
    return ReleaseInfo(
      version: version,
      name: title == null || title.isEmpty ? 'Spotifin $version' : title,
      url: url,
      publishedAt: publishedAt is String
          ? DateTime.tryParse(publishedAt)
          : null,
    );
  }

  final String version;
  final String name;
  final String url;
  final DateTime? publishedAt;
}
