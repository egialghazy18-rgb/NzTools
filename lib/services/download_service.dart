import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class DownloadService {
  static const _channel = MethodChannel('com.nzwx.nzdownloader/media');
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  /// Fast downloader with a safe fallback. Large files use parallel HTTP Range
  /// requests when the CDN supports them; otherwise it streams in one pass.
  static Future<String> download({
    required String url,
    required String fileName,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final safeName = _safeName(fileName);
    final tempFile = File('${tempDir.path}/$safeName');
    final client = HttpClient()
      ..userAgent = _ua
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30)
      ..autoUncompress = false;

    try {
      final uri = Uri.parse(url);
      final probe = await _probe(client, uri);

      if (probe.supportsRanges && probe.totalBytes >= 4 * 1024 * 1024) {
        try {
          await _parallelRangeDownload(
            client,
            uri,
            tempFile,
            probe.totalBytes,
            onProgress,
          );
        } on _RangeUnsupported {
          if (await tempFile.exists()) await tempFile.delete();
          await _singleDownload(client, uri, tempFile, probe.totalBytes, onProgress);
        }
      } else {
        await _singleDownload(client, uri, tempFile, probe.totalBytes, onProgress);
      }

      if (!await tempFile.exists() || await tempFile.length() == 0) {
        throw Exception('File hasil download kosong.');
      }

      final savedPath = await _channel.invokeMethod<String>('saveToDownloads', {
        'path': tempFile.path,
        'name': safeName,
        'mime': mimeType,
      });

      return savedPath ?? safeName;
    } on SocketException catch (e) {
      throw Exception('Koneksi terputus: ${e.message}');
    } on TimeoutException {
      throw Exception('Koneksi terlalu lama. Coba download lagi.');
    } finally {
      client.close(force: true);
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  static Future<_Probe> _probe(HttpClient client, Uri uri) async {
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(const Duration(seconds: 20));

      final contentRange = response.headers.value('content-range');
      final total = _parseTotal(contentRange) ??
          (response.statusCode == HttpStatus.ok ? response.contentLength : -1);
      final ranges = response.statusCode == HttpStatus.partialContent && total > 0;
      await response.drain<void>();
      return _Probe(total > 0 ? total : -1, ranges);
    } catch (_) {
      return const _Probe(-1, false);
    }
  }

  static int? _parseTotal(String? value) {
    if (value == null) return null;
    final match = RegExp(r'/([0-9]+)$').firstMatch(value.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static Future<void> _singleDownload(
    HttpClient client,
    Uri uri,
    File target,
    int knownTotal,
    void Function(double progress)? onProgress,
  ) async {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 20));
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Download gagal (${response.statusCode}).');
    }

    final total = knownTotal > 0 ? knownTotal : response.contentLength;
    var received = 0;
    final sink = target.openWrite();
    try {
      await sink.addStream(response.transform<List<int>>(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (chunk, out) {
            received += chunk.length;
            if (total > 0) onProgress?.call(received / total);
            out.add(chunk);
          },
        ),
      ));
    } finally {
      await sink.close();
    }
  }

  static Future<void> _parallelRangeDownload(
    HttpClient client,
    Uri uri,
    File target,
    int total,
    void Function(double progress)? onProgress,
  ) async {
    const workers = 4;
    final partDir = Directory('${target.parent.path}/nz_parts_${DateTime.now().microsecondsSinceEpoch}');
    await partDir.create(recursive: true);

    var completed = 0;
    final partFiles = <File>[];
    try {
      final futures = <Future<void>>[];
      for (var i = 0; i < workers; i++) {
        final start = (total * i) ~/ workers;
        final end = i == workers - 1 ? total - 1 : ((total * (i + 1)) ~/ workers) - 1;
        final part = File('${partDir.path}/part_$i');
        partFiles.add(part);
        futures.add(_downloadRange(client, uri, part, start, end, (bytes) {
          completed += bytes;
          onProgress?.call((completed / total).clamp(0.0, 1.0));
        }));
      }
      await Future.wait(futures);

      final output = target.openWrite();
      try {
        for (final part in partFiles) {
          await output.addStream(part.openRead());
        }
      } finally {
        await output.close();
      }
      onProgress?.call(1.0);
    } finally {
      try {
        if (await partDir.exists()) await partDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<void> _downloadRange(
    HttpClient client,
    Uri uri,
    File part,
    int start,
    int end,
    void Function(int bytes) onBytes,
  ) async {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 20));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.partialContent) {
      await response.drain<void>();
      throw _RangeUnsupported();
    }

    var received = 0;
    final sink = part.openWrite();
    try {
      await sink.addStream(response.transform<List<int>>(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (chunk, out) {
            received += chunk.length;
            onBytes(chunk.length);
            out.add(chunk);
          },
        ),
      ));
    } finally {
      await sink.close();
    }

    final expected = end - start + 1;
    if (received != expected) {
      throw Exception('Sebagian file tidak terunduh.');
    }
  }

  static String _safeName(String value) {
    var name = value.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), '_').trim();
    if (name.isEmpty) name = 'NzTools_${DateTime.now().millisecondsSinceEpoch}';
    return name.length > 90 ? name.substring(0, 90) : name;
  }
}

class _Probe {
  final int totalBytes;
  final bool supportsRanges;
  const _Probe(this.totalBytes, this.supportsRanges);
}

class _RangeUnsupported implements Exception {}
