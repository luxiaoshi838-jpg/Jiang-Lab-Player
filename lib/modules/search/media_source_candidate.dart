/// One concrete rule hit; a metadata catalog entry is never a video source.
class MediaSourceCandidate {
  const MediaSourceCandidate({
    required this.pluginName,
    required this.title,
    required this.url,
    this.imageUrl = '',
  });

  final String pluginName;
  final String title;
  final String url;
  final String imageUrl;

  String get identity => '${pluginName.toLowerCase()}|${url.trim()}';
}
