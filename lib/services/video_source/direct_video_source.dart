import 'package:kazumi/services/video_source/video_source_format.dart';

/// Return a format only for an unambiguous, ordinary HTTP(S) media URL.
///
/// An arbitrary video page, short-link, DASH manifest, or DRM stream must still
/// use the existing rule/page resolver. Queries and fragments are allowed.
VideoSourceFormat? directVideoFormat(String source) {
  final uri = Uri.tryParse(source.trim());
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty) {
    return null;
  }
  final path = uri.path.toLowerCase();
  if (path.endsWith('.m3u8')) return VideoSourceFormat.hls;
  if (path.endsWith('.mp4') || path.endsWith('.m4v')) {
    return VideoSourceFormat.auto;
  }
  return null;
}
