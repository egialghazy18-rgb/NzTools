
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'instagram_api.dart';

class TikTokApi {
  static const _base = 'https://ssstik.io';
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static Future<Map<String, dynamic>> fetch(String input) async {
    final clean = input.trim();
    final normalized = clean.split('#').first;
    final uri = Uri.tryParse(normalized);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw Exception('Masukkan URL media yang valid.');
    }

    // Instagram posts/reels are resolved through the dedicated Instagram connector.
    if (InstagramApi.supports(normalized)) {
      return InstagramApi.fetch(normalized);
    }

    // Prefer the universal Node backend when configured. This lets NzTools use
    // the multi-platform Scrapr engine without putting scraper code into the APK.
    const backend = String.fromEnvironment('NZTOOLS_API_URL', defaultValue: '');
    if (backend.trim().isNotEmpty) {
      try {
        return await _fetchBackend(normalized, backend.trim());
      } catch (_) {
        // Fall through to the existing direct/TikTok resolver below.
      }
    }

    // Generic direct-media support: MP4/MP3/images can be downloaded without
    // tying the app to a single social platform.
    if (_isDirectMediaUri(uri)) {
      final path = uri.path.toLowerCase();
      final ext = path.split('.').last;
      final type = _directType(ext);
      final title = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'Media';
      return {
        'status': true,
        'result': {
          'title': title.isEmpty ? 'Media' : title,
          'author': 'Direct media',
          'thumbnail': '',
          'type': type == 'music' ? 'audio' : type == 'photo' ? 'photo' : 'video',
          'downloads': [
            {'type': type, 'label': 'Direct ${ext.toUpperCase()}', 'url': normalized},
          ],
        }
      };
    }

    final tiktok = RegExp(r'^https:\/\/(?:(?:m|www|vm|vt|lite)\.)?tiktok\.com\/', caseSensitive: false);
    if (!tiktok.hasMatch(normalized)) {
      throw Exception('Platform belum punya resolver aktif. Direct MP4/MP3/image tetap didukung.');
    }
    final cleanTikTok = normalized.split('?').first;

    final home = await http.get(
      Uri.parse('$_base/id'),
      headers: {
        'User-Agent': _ua,
        'Accept': 'text/html,application/xhtml+xml,*/*;q=0.9',
        'Accept-Language': 'id-ID,id;q=0.9,en;q=0.8',
        'Referer': 'https://www.google.com/',
      },
    ).timeout(const Duration(seconds: 20));

    if (home.statusCode != 200) {
      throw Exception('Server resolver tidak merespons (${home.statusCode}).');
    }

    final tt = RegExp(r"""s_tt\s*=\s*['"]([^'"]+)['"]""",
            caseSensitive: false)
        .firstMatch(home.body)
        ?.group(1) ?? '';
    final furl = RegExp(r"""s_furl\s*=\s*['"]([^'"]+)['"]""",
            caseSensitive: false)
        .firstMatch(home.body)
        ?.group(1) ?? '';

    if (tt.isEmpty || furl.isEmpty) {
      throw Exception('Token resolver tidak ditemukan. Coba lagi nanti.');
    }

    final cookies = home.headers['set-cookie']
            ?.split(RegExp(r', (?=[^;,]+=)'))
            .map((x) => x.split(';').first.trim())
            .where((x) => x.isNotEmpty)
            .join('; ') ??
        '';

    final response = await http.post(
      Uri.parse('$_base/$furl?url=dl'),
      headers: {
        'User-Agent': _ua,
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Accept': 'text/html, */*; q=0.01',
        'Accept-Language': 'id-ID,id;q=0.9,en;q=0.8',
        'Referer': '$_base/id',
        'Origin': _base,
        'HX-Request': 'true',
        'HX-Current-URL': '$_base/id',
        'HX-Target': 'target',
        'HX-Trigger': 'main_page_text',
        if (cookies.isNotEmpty) 'Cookie': cookies,
      },
      body: Uri(queryParameters: {'id': cleanTikTok, 'locale': 'id', 'tt': tt}).query,
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Server media tidak merespons (${response.statusCode}).');
    }

    final document = parser.parse(response.body);
    final html = response.body;

    if (html.contains('sssblockedclient')) {
      throw Exception('Request diblokir oleh resolver. Coba lagi.');
    }
    if (html.contains('sssinvalidlink')) {
      throw Exception('Link TikTok tidak valid atau sudah tidak tersedia.');
    }

    final title = _text(document.querySelector('h2 + p')) ??
        _text(document.querySelector('.maintext p')) ??
        _text(document.querySelector('h3')) ??
        'TikTok Content';

    final author = _text(document.querySelector('h2')) ?? _authorFromUrl(cleanTikTok);

    final thumbnail = _attr(document.querySelector('img'), 'src') ??
        _attr(document.querySelector('meta[property="og:image"]'), 'content') ??
        '';

    final downloads = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final a in document.querySelectorAll('a[href]')) {
      final href0 = _attr(a, 'href');
      if (href0 == null || href0.isEmpty || href0 == '#') continue;

      final href = _absolute(href0);
      final label = a.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      final attrs = a.attributes.toString();

      final looksLikeDownload =
          href.contains('/d/') ||
          attrs.toLowerCase().contains('download') ||
          RegExp(r'\.(mp4|mp3|webm|m4a)(?:$|\?)', caseSensitive: false)
              .hasMatch(href) ||
          RegExp(r'tanpa.?tanda|no.?watermark|unduh|download|mp3|mp4|audio|hd',
                  caseSensitive: false)
              .hasMatch(label);

      if (!looksLikeDownload) continue;
      if (RegExp(r'watch.?ads|fitur.?pro|aplikasi', caseSensitive: false)
          .hasMatch(label)) continue;
      if (seen.contains(href)) continue;

      seen.add(href);
      downloads.add({
        'type': _classify(label, href),
        'label': label.isEmpty ? 'Download' : label,
        'url': href,
      });
    }

    if (downloads.isEmpty) {
      throw Exception(
          'Media TikTok tidak ditemukan. Resolver mungkin sedang berubah.');
    }

    return {
      'status': true,
      'result': {
        'title': title,
        'author': author,
        'thumbnail': _absolute(thumbnail),
        'type': 'video',
        'downloads': downloads,
      }
    };
  }

  static Future<Map<String, dynamic>> _fetchBackend(String url, String backend) async {
    final base = backend.replaceFirst(RegExp(r'/+$'), '');
    final response = await http.get(
      Uri.parse('$base/api/resolve').replace(queryParameters: {'url': url}),
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'NzTools/2.4 Android',
      },
    ).timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Backend resolver gagal (${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['status'] != true) {
      throw Exception('${decoded is Map ? decoded['message'] ?? 'Resolver gagal.' : 'Resolver gagal.'}');
    }
    final result = Map<String, dynamic>.from(decoded['result'] ?? {});
    final raw = result['downloads'];
    if (raw is! List || raw.isEmpty) throw Exception('Media tidak ditemukan.');
    final downloads = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).where((e) {
      final u = '${e['url'] ?? ''}'.trim();
      return u.startsWith('http://') || u.startsWith('https://');
    }).toList();
    if (downloads.isEmpty) throw Exception('Link download tidak ditemukan.');
    return {'status': true, 'result': {...result, 'downloads': downloads}};
  }

  static bool _isDirectMediaUri(Uri uri) {
    final p = uri.path.toLowerCase();
    return RegExp(r'\.(mp4|m4v|webm|mov|mkv|mp3|m4a|wav|ogg|flac|jpg|jpeg|png|webp|gif)$').hasMatch(p);
  }

  static String _directType(String ext) {
    if (RegExp(r'^(mp3|m4a|wav|ogg|flac)$').hasMatch(ext)) return 'music';
    if (RegExp(r'^(jpg|jpeg|png|webp|gif)$').hasMatch(ext)) return 'photo';
    return 'video';
  }

  static String _authorFromUrl(String url) {
    final m = RegExp(r'/@([^/]+)').firstMatch(url);
    return m?.group(1) ?? 'Unknown';
  }

  static String? _text(dynamic element) {
    final value = element?.text.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String? _attr(dynamic element, String name) {
    final value = element?.attributes[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String _absolute(String value) {
    if (value.isEmpty) return '';
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    return Uri.parse(_base).resolve(value).toString();
  }

  static String _classify(String label, String href) {
    final l = label.toLowerCase();
    if (RegExp(r'tanpa.?tanda.?air.*(hd|high)|no.?watermark.*(hd|high)')
        .hasMatch(l)) return 'video_hd_no_watermark';
    if (RegExp(r'tanpa.?tanda.?air|no.?watermark').hasMatch(l)) {
      return 'video_no_watermark';
    }
    if (l.contains('mp3') || l.contains('audio') || l.contains('music') ||
        RegExp(r'\.mp3(?:$|\?)').hasMatch(href)) return 'music';
    return 'video';
  }
}
