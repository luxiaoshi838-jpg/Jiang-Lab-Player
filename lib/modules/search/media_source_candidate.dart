/// One concrete rule hit; a metadata catalog entry is never a video source.
class MediaSourceCandidate {
  const MediaSourceCandidate({
    required this.pluginName,
    required this.title,
    required this.url,
    this.imageUrl = '',
    this.mediaType = 0,
  });

  final String pluginName;
  final String title;
  final String url;
  final String imageUrl;
  /// Confirmed anime=2; live action=6; 0 means not specified by the rule.
  final int mediaType;

  String get identity => '${pluginName.toLowerCase()}|${url.trim()}';
}
