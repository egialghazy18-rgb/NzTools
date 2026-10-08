import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'services/download_service.dart';
import 'services/tiktok_api.dart';
import 'services/instagram_api.dart';

const _paper = Color(0xFFF7F3EA);
const _card = Color(0xFFFFFCF6);
const _ink = Color(0xFF171716);
const _muted = Color(0xFF77746D);
const _line = Color(0xFF252421);
const _softLine = Color(0xFFD7D1C5);
const _soft = Color(0xFFEAE5DA);
const _green = Color(0xFF53604A);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NzToolsApp());
}

class NzToolsApp extends StatelessWidget {
  const NzToolsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NzTools',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: _paper,
        colorScheme: ColorScheme.fromSeed(seedColor: _ink, brightness: Brightness.light),
        fontFamily: 'sans',
        splashFactory: InkRipple.splashFactory,
        appBarTheme: const AppBarTheme(backgroundColor: _paper, foregroundColor: _ink, elevation: 0),
        navigationBarTheme: const NavigationBarThemeData(
          height: 78,
          backgroundColor: _card,
          indicatorColor: _soft,
          elevation: 0,
        ),
        inputDecorationTheme: const InputDecorationTheme(border: InputBorder.none, hintStyle: TextStyle(color: _muted)),
      ),
      home: const AppSplashGate(),
    );
  }
}


class AppSplashGate extends StatefulWidget {
  const AppSplashGate({super.key});

  @override
  State<AppSplashGate> createState() => _AppSplashGateState();
}

class _AppSplashGateState extends State<AppSplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _scale = Tween<double>(begin: .90, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
    Future<void>.delayed(const Duration(milliseconds: 1250), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _ready
          ? const NzHomePage(key: ValueKey('home'))
          : Scaffold(
              key: const ValueKey('splash'),
              backgroundColor: Colors.black,
              body: SafeArea(
                child: Center(
                  child: FadeTransition(
                    opacity: _fade,
                    child: ScaleTransition(
                      scale: _scale,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 154,
                            height: 154,
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B0C0F),
                              borderRadius: BorderRadius.circular(36),
                              border: Border.all(color: Colors.white12),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 32,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/nz_logo.png',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                          const SizedBox(height: 28),
                          const Text(
                            'NzTools',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 27,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.6,
                            ),
                          ),
                          const SizedBox(height: 7),
                          const Text(
                            'Downloader media platform.',
                            style: TextStyle(
                              color: Color(0xFF9B9DA3),
                              fontSize: 12.5,
                              letterSpacing: .15,
                            ),
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: 86,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: const LinearProgressIndicator(
                                minHeight: 2,
                                backgroundColor: Colors.white12,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'EGII  •  MEDIA UTILITY',
                            style: TextStyle(
                              color: Color(0xFF666970),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class NzHomePage extends StatefulWidget {
  const NzHomePage({super.key});
  @override
  State<NzHomePage> createState() => _NzHomePageState();
}

class _NzHomePageState extends State<NzHomePage> {
  int tab = 0;
  String preferredFormat = 'MP4';
  String preferredQuality = 'Best';
  bool autoAnalyzePaste = true;
  bool saveHistory = true;
  bool clipboardDetection = true;
  bool fetching = false;
  bool clipboardFound = false;
  String clipboardLink = '';
  final urlController = TextEditingController();
  final List<Map<String, String>> history = [];
  final List<Map<String, String>> downloads = [];
  Map<String, dynamic>? result;
  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 650), _checkClipboard);
    });
  }

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_home(), _history(), _dev(), _settings()];
    return Scaffold(
      backgroundColor: _paper,
      body: SafeArea(child: IndexedStack(index: tab, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'HOME'),
          NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history_rounded), label: 'HISTORY'),
          NavigationDestination(icon: Icon(Icons.code_outlined), selectedIcon: Icon(Icons.code_rounded), label: 'DEV'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'SETTINGS'),
        ],
      ),
    );
  }

  Widget _home() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
      children: [
        Row(children: [
          const NzLogo(size: 38),
          const SizedBox(width: 11),
          const Expanded(child: Text('NzTools', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.3))),
          _roundButton(Icons.info_outline_rounded, _showAbout),
        ]),
        const SizedBox(height: 28),
        const Text('Download media without the noise.', style: TextStyle(fontSize: 28, height: 1.08, fontWeight: FontWeight.w800, letterSpacing: -.8)),
        const SizedBox(height: 8),
        const Text('Downloader media platform. Paste a media link, preview it, then save the format you need.', style: TextStyle(color: _muted, fontSize: 13.5, height: 1.45)),
        const SizedBox(height: 20),
        _urlField(),
        if (clipboardFound) ...[
          const SizedBox(height: 9),
          _clipboardBanner(),
        ],
        const SizedBox(height: 10),
        _platformStrip(),
        const SizedBox(height: 12),
        SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: fetching ? null : _fetchPreview,
            style: FilledButton.styleFrom(backgroundColor: _ink, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
            child: fetching
                ? const SizedBox(width: 21, height: 21, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('ANALYZE', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ),
        ),
        if (result != null) ...[
          const SizedBox(height: 30),
          _resultCard(),
        ] else ...[
          const SizedBox(height: 26),
          _featureStrip(),
        ],
      ],
    );
  }

  Widget _urlField() {
    return Container(
      height: 58,
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(15), border: Border.all(color: _line, width: 1.15)),
      child: Row(children: [
        const SizedBox(width: 14),
        const Icon(Icons.search_rounded, size: 23, color: _ink),
        const SizedBox(width: 10),
        Expanded(child: TextField(
          controller: urlController,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _fetchPreview(),
          style: const TextStyle(color: _ink, fontSize: 14),
          decoration: const InputDecoration(hintText: 'Paste media URL'),
        )),
        IconButton(onPressed: _pasteOnly, icon: const Icon(Icons.content_paste_rounded, size: 20, color: _ink)),
        IconButton(onPressed: () => setState(() { urlController.clear(); result = null; items = []; }), icon: const Icon(Icons.close_rounded, size: 22, color: _ink)),
        const SizedBox(width: 4),
      ]),
    );
  }

  Widget _clipboardBanner() {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 8, 11),
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _softLine),
      ),
      child: Row(
        children: [
          const Icon(Icons.link_rounded, size: 19, color: _ink),
          const SizedBox(width: 9),
          const Expanded(
            child: Text('Media link detected in clipboard', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () async {
              setState(() { urlController.text = clipboardLink; clipboardFound = false; });
              await _fetchPreview();
            },
            child: const Text('ANALYZE', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: () => setState(() => clipboardFound = false),
            icon: const Icon(Icons.close_rounded, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Future<void> _checkClipboard() async {
    if (!clipboardDetection || !mounted) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      final uri = Uri.tryParse(text);
      if (text.isNotEmpty && uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        if (text != urlController.text.trim() && mounted) {
          setState(() {
            clipboardLink = text;
            clipboardFound = true;
          });
        }
      }
    } catch (_) {}
  }

  Widget _platformStrip() {
    const labels = ['TikTok', 'Instagram', 'Direct MP4', 'Direct MP3', 'Images'];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(20)),
          child: Text(labels[i], style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _ink)),
        ),
      ),
    );
  }

  Widget _featureStrip() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(15), border: Border.all(color: _softLine)),
      child: const Row(children: [
        Icon(Icons.play_circle_outline_rounded, size: 24, color: _ink),
        SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Preview before saving', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
          SizedBox(height: 3),
          Text('MP4 can be watched from start to finish. MP3 can be listened to before saving.', style: TextStyle(color: _muted, fontSize: 11.5, height: 1.35)),
        ])),
      ]),
    );
  }

  Widget _resultCard() {
    final r = result!;
    final title = '${r['title'] ?? 'Media'}';
    final platform = '${r['platform'] ?? (urlController.text.toLowerCase().contains('instagram.com') ? 'Instagram' : 'TikTok')}';
    final author = '${r['author'] ?? 'Unknown'}';
    final thumb = '${r['thumbnail'] ?? ''}';
    final video = items.cast<Map<String, dynamic>?>().firstWhere((x) => x != null && '${x['type'] ?? ''}' != 'music' && '${x['type'] ?? ''}' != 'photo', orElse: () => null);
    final audio = items.cast<Map<String, dynamic>?>().firstWhere((x) => x != null && '${x['type'] ?? ''}' == 'music', orElse: () => null);
    final photo = items.cast<Map<String, dynamic>?>().firstWhere((x) => x != null && '${x['type'] ?? ''}' == 'photo', orElse: () => null);
    return Container(
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(17), border: Border.all(color: _softLine)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 15, 15, 12),
          child: Row(children: [
            _thumb(thumb, width: 48, height: 60),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('READY TO DOWNLOAD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.0, color: _muted)),
                const Spacer(),
                Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(20)), child: Text(platform.toUpperCase(), style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: .7))),
              ]),
              const SizedBox(height: 5),
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.15)),
              const SizedBox(height: 4),
              Text('@$author', style: const TextStyle(color: _muted, fontSize: 12)),
            ])),
          ]),
        ),
        if (video != null) _InlineVideoPreview(url: '${video['url']}', thumbnail: thumb),
        if (video == null && thumb.isNotEmpty) SizedBox(height: 330, width: double.infinity, child: Image.network(thumb, fit: BoxFit.cover)),
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (video != null) _qualityDownloadSection(video),
              if (audio != null) ...[
                const SizedBox(height: 9),
                _downloadButton(audio, 'MP3', Icons.music_note_outlined),
              ],
              if (photo != null) ...[
                const SizedBox(height: 9),
                _downloadButton(photo, 'JPG / IMAGE', Icons.image_outlined),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  Widget _qualityDownloadSection(Map<String, dynamic> bestVideo) {
    final videos = items.where((x) {
      final type = '${x['type'] ?? ''}';
      return type != 'music' && type != 'photo';
    }).toList();
    final hdItem = videos.cast<Map<String, dynamic>?>().firstWhere(
      (x) => x?['verified1080'] == true,
      orElse: () => null,
    );
    final bestItem = videos.firstWhere(
      (x) => !identical(x, hdItem),
      orElse: () => bestVideo,
    );

    if (preferredQuality == '1080P' && hdItem != null) {
      // Put verified 1080P first when the user prefers it.
    }
    final first = preferredQuality == '1080P' && hdItem != null ? hdItem : bestItem;
    final second = identical(first, hdItem) ? bestItem : hdItem;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('VIDEO QUALITY  •  $preferredQuality', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: _muted)),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(child: _downloadButton(first, first == hdItem ? 'MP4 • HD 1080P' : 'MP4 • BEST', first == hdItem ? Icons.high_quality_rounded : Icons.movie_outlined)),
            if (second != null && !identical(first, second)) ...[
              const SizedBox(width: 8),
              Expanded(child: _downloadButton(second, second == hdItem ? 'MP4 • HD 1080P' : 'MP4 • BEST', second == hdItem ? Icons.high_quality_rounded : Icons.movie_outlined)),
            ],
          ],
        ),
        if (hdItem != null) ...[
          const SizedBox(height: 5),
          Text(
            'HD 1080P terverifikasi • ${hdItem['width']}×${hdItem['height']} • bukan sekadar label.',
            style: const TextStyle(color: _green, fontSize: 10.5, fontWeight: FontWeight.w700),
          ),
        ] else ...[
          const SizedBox(height: 5),
          const Text('HD 1080P hanya ditampilkan jika resolusi media benar-benar terverifikasi.', style: TextStyle(color: _muted, fontSize: 10.5)),
        ],
      ],
    );
  }

  Future<void> _verifyVideoQualities(List<Map<String, dynamic>> list) async {
    final videos = list.where((x) {
      final type = '${x['type'] ?? ''}';
      return type != 'music' && type != 'photo';
    }).take(4).toList();

    for (final item in videos) {
      if (!mounted) return;
      VideoPlayerController? probe;
      try {
        probe = VideoPlayerController.networkUrl(Uri.parse('${item['url']}'));
        await probe.initialize().timeout(const Duration(seconds: 10));
        final size = probe.value.size;
        item['width'] = size.width.round();
        item['height'] = size.height.round();
        item['verified1080'] = size.width >= 1920 && size.height >= 1080;
      } catch (_) {
        item['verified1080'] = false;
      } finally {
        await probe?.dispose();
      }
    }
    if (mounted) setState(() {});
  }

  Widget _downloadButton(Map<String, dynamic>? item, String label, IconData icon) {
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: item == null ? null : () => _startDownload(item, label),
        style: FilledButton.styleFrom(backgroundColor: _ink, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
        icon: Icon(icon, size: 18),
        label: Text('DOWNLOAD $label', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .5)),
      ),
    );
  }

  Future<void> _pasteOnly() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) { _snack('Clipboard tidak berisi link.'); return; }
    setState(() => urlController.text = text);
    if (autoAnalyzePaste) await _fetchPreview();
  }

  Future<void> _fetchPreview() async {
    final url = urlController.text.trim();
    if (url.isEmpty) { _snack('Masukkan link media dulu.'); return; }
    FocusScope.of(context).unfocus();
    setState(() { fetching = true; result = null; items = []; });
    try {
      final isInstagram = InstagramApi.supports(url);
      final data = isInstagram ? await InstagramApi.fetch(url) : await TikTokApi.fetch(url);
      if (!mounted) return;
      final r = Map<String, dynamic>.from(data['result'] ?? {});
      final list = (r['downloads'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
      setState(() {
        result = r;
        items = list;
        clipboardFound = false;
        if (saveHistory) {
          history.insert(0, {'title': '${r['title'] ?? 'Media'}', 'author': '${r['author'] ?? 'Unknown'}', 'thumb': '${r['thumbnail'] ?? ''}'});
          if (history.length > 50) history.removeRange(50, history.length);
        }
      });
      unawaited(_saveSettings());
      unawaited(_verifyVideoQualities(list));
    } catch (e) {
      if (mounted) _snack('Gagal mengambil media: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally { if (mounted) setState(() => fetching = false); }
  }

  Future<void> _startDownload(Map<String, dynamic> item, String label) async {
    final type = '${item['type'] ?? 'video'}';
    final ext = type == 'music' ? 'mp3' : type == 'photo' ? 'jpg' : 'mp4';
    final mime = type == 'music' ? 'audio/mpeg' : type == 'photo' ? 'image/jpeg' : 'video/mp4';
    final name = 'Nz_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final progress = ValueNotifier<double>(0);
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
      backgroundColor: _card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Saving media', style: TextStyle(fontWeight: FontWeight.w800)),
      content: ValueListenableBuilder<double>(valueListenable: progress, builder: (_, value, __) => Column(mainAxisSize: MainAxisSize.min, children: [
        LinearProgressIndicator(value: value <= 0 ? null : value, minHeight: 5, borderRadius: BorderRadius.circular(5)),
        const SizedBox(height: 12),
        Text(value <= 0 ? 'Connecting…' : '${(value * 100).toStringAsFixed(0)}%', style: const TextStyle(color: _muted, fontSize: 12)),
      ])),
    ));
    try {
      final saved = await DownloadService.download(url: '${item['url']}', fileName: name, mimeType: mime, onProgress: (p) => progress.value = p);
      if (!mounted) return;
      Navigator.of(context).pop();
      progress.dispose();
      downloads.insert(0, {'name': name, 'type': label, 'path': saved});
      setState(() {});
      _snack('Saved to Downloads/NzTools');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      progress.dispose();
      _snack('Download gagal: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Widget _history() => _listPage('History', 'Recent links you analyzed', Icons.history_rounded, history, (x) => '${x['title']}');

  Widget _listPage(String title, String subtitle, IconData icon, List<Map<String, String>> list, String Function(Map<String, String>) label) {
    return ListView(padding: const EdgeInsets.fromLTRB(22, 25, 22, 30), children: [
      const Text('History', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800, letterSpacing: -.7)),
      const SizedBox(height: 4),
      Text(subtitle, style: const TextStyle(color: _muted, fontSize: 13)),
      const SizedBox(height: 20),
      if (list.isEmpty)
        Padding(padding: const EdgeInsets.only(top: 150), child: Column(children: [Icon(icon, size: 42, color: _muted), const SizedBox(height: 12), const Text('No history yet', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 5), const Text('Analyzed links will appear here.', style: TextStyle(color: _muted, fontSize: 12))]))
      else ...list.map((x) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _softLine)),
        child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), leading: x['thumb']?.isNotEmpty == true ? _thumb(x['thumb']!, width: 48, height: 56) : const Icon(Icons.movie_outlined, color: _muted), title: Text(label(x), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)), subtitle: Text(x['author'] ?? '', style: const TextStyle(color: _muted, fontSize: 11.5))),
      )),
    ]);
  }

  Widget _dev() => ListView(
    padding: const EdgeInsets.fromLTRB(22, 25, 22, 30),
    children: [
      const Text('Dev', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800, letterSpacing: -.7)),
      const SizedBox(height: 4),
      const Text('Built, maintained and designed by Egii.', style: TextStyle(color: _muted, fontSize: 13)),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(17), border: Border.all(color: _softLine)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const NzLogo(size: 66),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('Egii', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -.3)),
            SizedBox(height: 4),
            Text('Developer & Creator', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _muted)),
            SizedBox(height: 10),
            Text('Building practical tools with a clean interface, reliable media workflows, and a focus on simple experiences that just make sense.', style: TextStyle(fontSize: 12.5, height: 1.45, color: _ink)),
          ])),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(15)),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('NZTOOLS', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
          SizedBox(height: 7),
          Text('A lightweight media utility built to stay fast, focused and easy to use.', style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4)),
        ]),
      ),
    ],
  );

  Widget _settings() => ListView(
    padding: const EdgeInsets.fromLTRB(22, 25, 22, 30),
    children: [
      const Text('Settings', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800, letterSpacing: -.7)),
      const SizedBox(height: 4),
      const Text('Control how NzTools handles media.', style: TextStyle(color: _muted, fontSize: 13)),
      const SizedBox(height: 22),
      _settingsSection('DOWNLOAD', [
        _setting(Icons.swap_horiz_rounded, 'Preferred format', preferredFormat, () => _chooseOption(
          'Preferred format', ['MP4', 'MP3'], preferredFormat, (v) { setState(() => preferredFormat = v); _saveSettings(); })),
        _setting(Icons.high_quality_outlined, 'Preferred video quality', preferredQuality, () => _chooseOption(
          'Preferred video quality', ['Best', '1080P', '720P'], preferredQuality, (v) { setState(() => preferredQuality = v); _saveSettings(); })),
        _setting(Icons.folder_outlined, 'Download folder', 'Downloads/NzTools', () => _snack('Media akan disimpan ke Downloads/NzTools.')),
      ]),
      const SizedBox(height: 18),
      _settingsSection('BEHAVIOR', [
        _toggleSetting(Icons.content_paste_go_rounded, 'Auto Analyze after Paste', 'Paste link lalu langsung Analyze', autoAnalyzePaste, (v) { setState(() => autoAnalyzePaste = v); _saveSettings(); }),
        _toggleSetting(Icons.link_rounded, 'Clipboard Detection', 'Tawarkan link yang baru disalin saat membuka NzTools', clipboardDetection, (v) { setState(() => clipboardDetection = v); _saveSettings(); }),
        _toggleSetting(Icons.history_rounded, 'Save History', 'Simpan link yang berhasil dianalisis', saveHistory, (v) { setState(() => saveHistory = v); _saveSettings(); }),
      ]),
      const SizedBox(height: 18),
      _settingsSection('STORAGE', [
        _setting(Icons.delete_sweep_outlined, 'Clear history', '${history.length} item', () => _confirmClearHistory()),
        _setting(Icons.cleaning_services_outlined, 'Clear preview cache', 'Remove temporary media files', () => _clearPreviewCache()),
      ]),
      const SizedBox(height: 18),
      _settingsSection('ABOUT', [
        _setting(Icons.info_outline_rounded, 'About NzTools', 'Version 2.2.0', _showAbout),
      ]),
    ],
  );

  Widget _settingsSection(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: _muted)),
      const SizedBox(height: 8),
      ...children,
    ],
  );

  Widget _setting(IconData icon, String title, String subtitle, VoidCallback onTap) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _softLine)),
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
      leading: Icon(icon, color: _ink, size: 21),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
      subtitle: Text(subtitle, style: const TextStyle(color: _muted, fontSize: 11.5)),
      trailing: const Icon(Icons.chevron_right_rounded, color: _muted),
    ),
  );

  Widget _toggleSetting(IconData icon, String title, String subtitle, bool value, ValueChanged<bool> onChanged) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _softLine)),
    child: ListTile(
      contentPadding: const EdgeInsets.only(left: 13, right: 8, top: 3, bottom: 3),
      leading: Icon(icon, color: _ink, size: 21),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
      subtitle: Text(subtitle, style: const TextStyle(color: _muted, fontSize: 11.5)),
      trailing: Switch(value: value, onChanged: onChanged),
    ),
  );

  Future<File> _settingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/nztools_settings.json');
  }

  Future<void> _loadSettings() async {
    try {
      final f = await _settingsFile();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        preferredFormat = '${raw['format'] ?? preferredFormat}';
        preferredQuality = '${raw['quality'] ?? preferredQuality}';
        autoAnalyzePaste = raw['autoAnalyze'] != false;
        clipboardDetection = raw['clipboardDetection'] != false;
        saveHistory = raw['saveHistory'] != false;
        final savedHistory = raw['history'];
        if (savedHistory is List) {
          history
            ..clear()
            ..addAll(savedHistory.whereType<Map>().map((e) => Map<String, String>.from(e.map((k, v) => MapEntry('$k', '$v')))));
        }
      });
    } catch (_) {
    }
  }

  Future<void> _saveSettings() async {
    try {
      final f = await _settingsFile();
      await f.writeAsString(jsonEncode({
        'format': preferredFormat,
        'quality': preferredQuality,
        'autoAnalyze': autoAnalyzePaste,
        'clipboardDetection': clipboardDetection,
        'saveHistory': saveHistory,
        'history': history,
      }));
    } catch (_) {}
  }

  Future<void> _chooseOption(String title, List<String> options, String current, ValueChanged<String> onSelected) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ...options.map((option) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(option, style: const TextStyle(fontWeight: FontWeight.w700)),
            trailing: option == current ? const Icon(Icons.check_rounded) : null,
            onTap: () => Navigator.pop(context, option),
          )),
        ]),
      )),
    );
    if (selected != null) onSelected(selected);
  }

  Future<void> _confirmClearHistory() async {
    if (history.isEmpty) { _snack('History sudah kosong.'); return; }
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: _card,
      title: const Text('Clear history?'),
      content: const Text('Semua riwayat analisis akan dihapus dari sesi ini.', style: TextStyle(color: _muted)),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear'))],
    ));
    if (ok == true && mounted) { setState(() => history.clear()); await _saveSettings(); }
  }

  Future<void> _clearPreviewCache() async {
    try {
      final dir = await getTemporaryDirectory();
      var removed = 0;
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          final name = entity.path.toLowerCase();
          if (name.contains('nz_preview') || name.endsWith('.mp4') || name.endsWith('.mp3')) {
            try { await entity.delete(recursive: true); removed++; } catch (_) {}
          }
        }
      }
      if (mounted) _snack(removed == 0 ? 'Preview cache sudah bersih.' : 'Preview cache dibersihkan.');
    } catch (_) {
      if (mounted) _snack('Tidak bisa membersihkan cache.');
    }
  }

  Widget _thumb(String url, {required double width, required double height}) => ClipRRect(borderRadius: BorderRadius.circular(10), child: Container(width: width, height: height, color: _soft, child: url.isEmpty ? const Icon(Icons.image_outlined, color: _muted) : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined, color: _muted))));

  Widget _roundButton(IconData icon, VoidCallback onTap) => IconButton(onPressed: onTap, style: IconButton.styleFrom(backgroundColor: _card, side: const BorderSide(color: _softLine), shape: const CircleBorder()), icon: Icon(icon, size: 20, color: _ink));

  void _showAbout() => showDialog<void>(context: context, builder: (_) => AlertDialog(backgroundColor: _card, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), title: const Text('NzTools'), content: const Text('Downloader media platform with inline preview and quality-aware video options.\n\nVersion 2.2.0', style: TextStyle(color: _muted, height: 1.45)), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]));

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, backgroundColor: _ink));
}

class NzLogo extends StatelessWidget {
  final double size;
  const NzLogo({super.key, this.size = 64});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: EdgeInsets.all(size * .10),
    decoration: BoxDecoration(
      color: const Color(0xFF101112),
      borderRadius: BorderRadius.circular(size * .26),
      border: Border.all(color: const Color(0xFF2D2E30)),
      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 3))],
    ),
    child: Image.asset('assets/nz_logo.png', fit: BoxFit.contain, filterQuality: FilterQuality.high),
  );
}

class _InlineVideoPreview extends StatefulWidget {
  final String url;
  final String thumbnail;
  const _InlineVideoPreview({required this.url, required this.thumbnail});

  @override
  State<_InlineVideoPreview> createState() => _InlineVideoPreviewState();
}

class _InlineVideoPreviewState extends State<_InlineVideoPreview> {
  VideoPlayerController? controller;
  File? cachedFile;
  String? error;
  double cacheProgress = 0;
  bool caching = true;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final dir = Directory('${Directory.systemTemp.path}/nzwx_preview');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/${widget.url.hashCode.abs()}.mp4');

      if (!await file.exists() || await file.length() < 1024) {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 12);
        try {
          final request = await client.getUrl(Uri.parse(widget.url));
          request.headers.set(HttpHeaders.userAgentHeader,
              'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36');
          final response = await request.close().timeout(const Duration(seconds: 25));
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw Exception('Preview server returned ${response.statusCode}');
          }
          final total = response.contentLength;
          final sink = file.openWrite();
          var received = 0;
          await for (final chunk in response) {
            sink.add(chunk);
            received += chunk.length;
            if (mounted && total > 0) {
              setState(() => cacheProgress = received / total);
            }
          }
          await sink.flush();
          await sink.close();
        } finally {
          client.close(force: true);
        }
      }

      cachedFile = file;
      caching = false;
      if (mounted) setState(() {});
      final c = VideoPlayerController.file(file);
      controller = c;
      await c.initialize();
      await c.setLooping(false);
      if (mounted) setState(() {});
    } catch (_) {
      // A local cache is preferred because it prevents CDN buffering/stalling.
      // If caching fails, fall back to direct network playback.
      try {
        final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
        controller = c;
        caching = false;
        if (mounted) setState(() {});
        await c.initialize();
        await c.setLooping(false);
        if (mounted) setState(() {});
      } catch (e) {
        if (mounted) setState(() { caching = false; error = e.toString(); });
      }
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (error != null && c == null) return _fallback();
    if (c == null || !c.value.isInitialized) return _fallback(loading: true);

    return Container(
      color: Colors.black,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: c.value.aspectRatio == 0 ? 9 / 16 : c.value.aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoPlayer(c),
                Center(
                  child: ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: c,
                    builder: (_, value, __) {
                      return AnimatedOpacity(
                        opacity: value.isPlaying ? 0 : 1,
                        duration: const Duration(milliseconds: 160),
                        child: GestureDetector(
                          onTap: () => value.isPlaying ? c.pause() : c.play(),
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: const Icon(Icons.play_arrow_rounded, color: _ink, size: 34),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 8,
                  child: ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: c,
                    builder: (_, value, __) {
                      final max = value.duration.inMilliseconds <= 0 ? 1.0 : value.duration.inMilliseconds.toDouble();
                      final position = value.position.inMilliseconds.clamp(0, max.toInt()).toDouble();
                      return SliderTheme(
                        data: const SliderThemeData(trackHeight: 2.5, thumbShape: RoundSliderThumbShape(enabledThumbRadius: 4), overlayShape: RoundSliderOverlayShape(overlayRadius: 8)),
                        child: Slider(
                          value: position,
                          max: max,
                          activeColor: Colors.white,
                          inactiveColor: Colors.white38,
                          onChanged: (x) => c.seekTo(Duration(milliseconds: x.round())),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 5),
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: c,
              builder: (_, value, __) => Row(
                children: [
                  IconButton(onPressed: () => value.isPlaying ? c.pause() : c.play(), icon: Icon(value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white)),
                  IconButton(onPressed: () async { await c.seekTo(Duration.zero); await c.play(); }, icon: const Icon(Icons.replay_rounded, color: Colors.white)),
                  const Spacer(),
                  Text('${_fmt(value.position)} / ${_fmt(value.duration)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback({bool loading = false}) {
    return SizedBox(
      height: 330,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.thumbnail.isNotEmpty) Image.network(widget.thumbnail, fit: BoxFit.cover) else const ColoredBox(color: Colors.black12),
          if (loading)
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 42),
                padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
                decoration: BoxDecoration(color: Colors.black.withOpacity(.68), borderRadius: BorderRadius.circular(14)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Preparing preview', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: cacheProgress > 0 ? cacheProgress : null, minHeight: 4, borderRadius: BorderRadius.circular(4)),
                  const SizedBox(height: 7),
                  Text(cacheProgress > 0 ? '${(cacheProgress * 100).toStringAsFixed(0)}% • buffering to local preview' : 'Connecting…', style: const TextStyle(color: Colors.white70, fontSize: 10.5)),
                ]),
              ),
            )
          else
            const Center(child: Icon(Icons.movie_outlined, size: 44, color: _muted)),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}
