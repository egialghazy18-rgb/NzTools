import 'dart:convert';
import 'dart:io';

/// Instagram resolver for NzTools.
///
/// Primary path: a Node backend running yt-dlp + ffmpeg (recommended).
/// The backend URL is supplied at build time:
///   --dart-define=NZTOOLS_API_URL=https://your-api.example.com
///
/// A kol.id fallback is retained for compatibility, but yt-dlp backend is the
/// reliable path for public Instagram posts/reels.
class InstagramApi {
  static const _backend = String.fromEnvironment('NZTOOLS_API_URL', defaultValue: '');
  // Legacy Kol resolver remains in source for optional manual fallback only.
  static const _kol = 'https://kol.id';
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static final RegExp _instagram = RegExp(
    r'^https?://(?:www\.)?instagram\.com/(?:p|reel|reels|tv|stories)/[A-Za-z0-9_.-]+',
    caseSensitive: false,
  );

  static bool supports(String value) => _instagram.hasMatch(value.trim());

  static Future<Map<String, dynamic>> fetch(String input) async {
    final original = input.trim().split('#').first;
    if (!supports(original)) throw Exception('Link Instagram tidak valid.');

    if (_backend.trim().isNotEmpty) {
      // Once configured, backend errors are surfaced directly. Silently falling
      // back to a fragile third-party page hid the actual yt-dlp failure.
      return _fetchBackend(original);
    }

    throw Exception(
      'Backend NzTools belum dihubungkan. Deploy folder backend (Docker) yang berisi yt-dlp + ffmpeg, lalu build APK dengan --dart-define=NZTOOLS_API_URL=https://domain-backend-kamu.');
  }

  static Future<Map<String, dynamic>> _fetchBackend(String url) async {
    final base = _backend.trim().replaceFirst(RegExp(r'/+$'), '');
    final endpoint = Uri.parse('$base/api/instagram/resolve').replace(
      queryParameters: {'url': url},
    );
    final client = HttpClient()
      ..userAgent = _ua
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30);
    try {
      final req = await client.getUrl(endpoint).timeout(const Duration(seconds: 20));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 45));
      final body = await utf8.decoder.bind(res).join();
      final decoded = jsonDecode(body);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('${decoded is Map ? decoded['message'] ?? decoded['error'] : 'Instagram backend gagal'}');
      }
      if (decoded is! Map || decoded['status'] != true) {
        throw Exception('${decoded is Map ? decoded['message'] ?? decoded['error'] : 'Instagram backend gagal'}');
      }
      final r = Map<String, dynamic>.from(decoded['result'] ?? {});
      final downloads = (r['downloads'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (downloads.isEmpty) throw Exception('yt-dlp tidak menemukan media.');
      return {'status': true, 'result': {...r, 'platform': 'Instagram', 'downloads': downloads}};
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> _fetchKol(String original) async {
    final session = await _getSession();
    final candidates = <String>[original];
    final uri = Uri.tryParse(original);
    if (uri != null && uri.query.isNotEmpty) {
      candidates.add(uri.replace(query: '', fragment: '').toString());
    }
    String lastMessage = '';
    for (final candidate in candidates) {
      try {
        final raw = await _post(session.token, session.cookie, candidate);
        final ok = raw['sukses'] == true || raw['success'] == true;
        if (ok && raw['error'] == null) return _normalize(raw, candidate);
        lastMessage = '${raw['message'] ?? raw['error'] ?? ''}'.trim();
      } catch (e) {
        lastMessage = e.toString().replaceFirst('Exception: ', '');
      }
    }
    throw Exception(lastMessage.isEmpty
        ? 'Instagram gagal. Untuk resolver yang lebih stabil, hubungkan backend yt-dlp NzTools.'
        : lastMessage);
  }

  static Future<_Session> _getSession() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('$_kol/download-video/instagram'));
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
      req.headers.set(HttpHeaders.acceptHeader,
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await utf8.decoder.bind(res).join();
      final token = _extractToken(body);
      if (token == null || token.isEmpty) throw Exception('Token Instagram resolver tidak ditemukan.');
      final cookies = res.headers[HttpHeaders.setCookieHeader] ?? const <String>[];
      final cookie = cookies.map((v) => v.split(';').first.trim()).where((v) => v.contains('=')).join('; ');
      return _Session(token, cookie);
    } finally { client.close(force: true); }
  }

  static Future<Map<String, dynamic>> _post(String token, String cookie, String url) async {
    final body = Uri(queryParameters: {'url': url, '_token': token}).query;
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse('$_kol/api/v2/downloader/instagram'));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded; charset=UTF-8');
      req.headers.set(HttpHeaders.acceptHeader, '*/*');
      req.headers.set('X-Requested-With', 'XMLHttpRequest');
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
      req.headers.set(HttpHeaders.refererHeader, '$_kol/download-video/instagram');
      req.headers.set('origin', _kol);
      if (cookie.isNotEmpty) req.headers.set(HttpHeaders.cookieHeader, cookie);
      req.contentLength = utf8.encode(body).length;
      req.write(body);
      final res = await req.close().timeout(const Duration(seconds: 30));
      final responseBody = await utf8.decoder.bind(res).join();
      if (res.statusCode < 200 || res.statusCode >= 300) throw Exception('Instagram resolver gagal (${res.statusCode}).');
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) return decoded;
      return Map<String, dynamic>.from(decoded as Map);
    } finally { client.close(force: true); }
  }

  static Map<String, dynamic> _normalize(Map<String, dynamic> raw, String sourceUrl) {
    final data = raw['data'] is Map ? Map<String, dynamic>.from(raw['data'] as Map) : <String, dynamic>{};
    final candidates = [data['unduhan'], data['downloads'], data['medias'], data['links'], data['results'], raw['unduhan'], raw['medias'], raw['links'], raw['results']];
    List<dynamic> mediaList = const [];
    for (final c in candidates) { if (c is List && c.isNotEmpty) { mediaList = c; break; } }
    final downloads = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (var i = 0; i < mediaList.length; i++) {
      final item = mediaList[i]; if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final u = _cleanUrl('${map['url'] ?? map['link'] ?? map['src'] ?? map['download_url'] ?? ''}');
      if (u.isEmpty || !seen.add(u)) continue;
      final explicit = '${map['type'] ?? ''}'.toLowerCase();
      final video = explicit == 'video' || _looksLikeVideo(u);
      downloads.add({'url': u, 'quality': '${map['quality'] ?? map['resolution'] ?? 'media_${i + 1}'}', 'type': video ? 'video' : 'photo', 'label': '${map['label'] ?? (video ? 'Download Video' : 'Download Foto')}', 'size': map['size']});
    }
    if (downloads.isEmpty) {
      final u = _cleanUrl('${data['url'] ?? data['download_url'] ?? data['link'] ?? raw['url'] ?? ''}');
      if (u.isNotEmpty) downloads.add({'url': u, 'quality': 'standard', 'type': _looksLikeVideo(u) ? 'video' : 'photo', 'label': 'Download', 'size': null});
    }
    if (downloads.isEmpty) throw Exception('Media Instagram tidak ditemukan.');
    final hasVideo = downloads.any((x) => x['type'] == 'video');
    return {'status': true, 'result': {'title': '${data['title'] ?? raw['title'] ?? raw['caption'] ?? 'Instagram Content'}', 'author': '${data['author'] ?? 'Instagram'}', 'thumbnail': _cleanUrl('${data['thumbnail'] ?? data['thumb'] ?? data['cover'] ?? raw['thumbnail'] ?? ''}'), 'type': '${data['media_type'] ?? raw['type'] ?? (hasVideo ? 'video' : 'photo')}', 'platform': 'Instagram', 'downloads': downloads, 'source_url': '${data['source_url'] ?? sourceUrl}'}};
  }

  static String? _extractToken(String html) {
    for (final p in [RegExp(r'''name=["']_token["']\s+value=["']([^"']+)["']''', caseSensitive: false), RegExp(r'''csrf-token["']\s+content=["']([^"']+)["']''', caseSensitive: false), RegExp(r'''["']_token["']\s*:\s*["']([^"']+)["']''', caseSensitive: false)]) {
      final m = p.firstMatch(html); if (m != null) return m.group(1);
    }
    return null;
  }

  static String _cleanUrl(String value) => value.replaceAll(r'\/', '/').trim();
  static bool _looksLikeVideo(String url) => RegExp(r'\.(mp4|m4v)(?:$|\?)', caseSensitive: false).hasMatch(url) || RegExp(r'(video|reel)', caseSensitive: false).hasMatch(url);
}

class _Session { final String token; final String cookie; const _Session(this.token, this.cookie); }
