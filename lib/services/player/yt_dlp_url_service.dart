import 'dart:convert';
import 'dart:io';

/// Resolve an explicitly supplied public webpage URL to one combined stream.
/// Does not modify or replace Kazumi rules, search sources or danmaku.
class YtDlpUrlService {
  static Uri validate(String input) {
    final url = Uri.tryParse(input.trim());
    if (url == null || (url.scheme != 'https' && url.scheme != 'http') ||
        url.host.isEmpty || url.userInfo.isNotEmpty) {
      throw const YtDlpUrlException('请输入有效的 http(s) 视频网页地址');
    }
    final host = url.host.toLowerCase();
    if (host == 'localhost' || host.endsWith('.localhost') ||
        host.endsWith('.local') || host.endsWith('.internal')) {
      throw const YtDlpUrlException('不能解析本机或内网地址');
    }
    final ip = InternetAddress.tryParse(host);
    if (ip != null) {
      if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) {
        throw const YtDlpUrlException('不能解析本机或内网地址');
      }
      if (ip.type == InternetAddressType.IPv4) {
        final b = ip.rawAddress;
        if (b[0] == 0 || b[0] == 10 || b[0] == 127 ||
            (b[0] == 169 && b[1] == 254) ||
            (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
            (b[0] == 192 && b[1] == 168) || b[0] >= 224) {
          throw const YtDlpUrlException('不能解析本机或内网地址');
        }
      } else if (ip.rawAddress[0] == 0xfc || ip.rawAddress[0] == 0xfd) {
        throw const YtDlpUrlException('不能解析本机或内网地址');
      }
    }
    return url;
  }

  static YtDlpResolvedVideo fromJson(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const YtDlpUrlException('解析器没有返回有效的视频信息');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const YtDlpUrlException('视频信息格式不正确');
    }
    if (decoded['entries'] is List ||
        decoded['requested_formats'] is List) {
      throw const YtDlpUrlException('该链接仅有分离音视频轨道，尚不能直接播放');
    }
    final stream = decoded['url'];
    final mediaUrl = stream is String ? Uri.tryParse(stream) : null;
    if (mediaUrl == null ||
        (mediaUrl.scheme != 'https' && mediaUrl.scheme != 'http') ||
        mediaUrl.host.isEmpty) {
      throw const YtDlpUrlException('未找到可直接播放的媒体地址');
    }
    final headers = <String, String>{};
    final dataHeaders = decoded['http_headers'];
    if (dataHeaders is Map) {
      for (final item in dataHeaders.entries) {
        if (item.key is String && item.value is String &&
            (item.key as String).length <= 64 &&
            (item.value as String).length <= 8192) {
          headers[item.key as String] = item.value as String;
        }
      }
    }
    final title = decoded['title'];
    return YtDlpResolvedVideo(
      title: title is String && title.trim().isNotEmpty
          ? title.trim() : '在线视频',
      url: mediaUrl.toString(),
      headers: Map.unmodifiable(headers),
    );
  }

  Future<YtDlpResolvedVideo> resolve(String input) async {
    final url = validate(input);
    if (!Platform.isWindows) {
      throw const YtDlpUrlException('网址解析目前仅支持 Windows');
    }
    final location = File(Platform.resolvedExecutable).parent.path;
    final exe = File('$location/yt-dlp.exe');
    if (!await exe.exists()) {
      throw const YtDlpUrlException('缺少 yt-dlp 组件，请重新安装随播正式版');
    }
    Process process;
    try {
      process = await Process.start(exe.path, [
        '--ignore-config', '--no-playlist', '--no-warnings',
        '--no-progress', '--skip-download', '--dump-single-json',
        '-f', 'best[ext=mp4]/best', '--', url.toString(),
      ], runInShell: false);
    } on ProcessException {
      throw const YtDlpUrlException('无法启动 yt-dlp，检查安装文件是否完整');
    }

    final out = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.drain<void>();
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          process.kill();
          throw const YtDlpUrlException('解析超时，请稍后重试');
        },
      );
    } finally {
      process.kill();
    }
    final body = await out;
    await errors; // Never surface logs containing video tokens / cookies.
    if (exitCode != 0) {
      throw const YtDlpUrlException('解析失败：来源可能不可用、需要登录或受 DRM 保护');
    }
    if (body.length > 8 * 1024 * 1024) {
      throw const YtDlpUrlException('视频信息过大，已停止解析');
    }
    return fromJson(body);
  }
}

class YtDlpResolvedVideo {
  const YtDlpResolvedVideo({
    required this.title, required this.url, required this.headers,
  });
  final String title;
  final String url;
  final Map<String, String> headers;
}

class YtDlpUrlException implements Exception {
  const YtDlpUrlException(this.message);
  final String message;
  @override
  String toString() => message;
}
