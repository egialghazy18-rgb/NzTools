'use strict';
const express = require('express');
const cors = require('cors');
const { scrape } = require('./scraper');
const { resolveInstagram, validInstagramUrl } = require('./instagram_ytdlp');
const { resolveInstagramEmbed } = require('./instagram_embed');
const { resolveWithScrapr, detectPlatform } = require('./universal_scrapr');

const app = express();
const PORT = process.env.PORT || 3000;
app.disable('x-powered-by');
app.use(cors());
app.use(express.json({ limit: '64kb' }));

app.get('/health', (_q, s) => s.json({
  status: true,
  service: 'NzTools API',
  version: '2.4.1',
  engine: 'yt-dlp Instagram primary + Scrapr fallback',
}));

async function resolveUniversal(url) {
  const clean = String(url || '').trim();
  if (!/^https?:\/\//i.test(clean)) throw new Error('URL media tidak valid.');

  // Direct media links need no scraper.
  try {
    const u = new URL(clean);
    if (/\.(mp4|m4v|webm|mov|mp3|m4a|wav|ogg|jpg|jpeg|png|webp|gif)$/i.test(u.pathname)) {
      const ext = u.pathname.split('.').pop().toLowerCase();
      const type = /^(mp3|m4a|wav|ogg)$/.test(ext) ? 'music' : /^(jpg|jpeg|png|webp|gif)$/.test(ext) ? 'photo' : 'video';
      return { status: true, result: { title: decodeURIComponent(u.pathname.split('/').pop() || 'Media'), author: 'Direct media', thumbnail: '', type, platform: 'Direct', source_url: clean, downloads: [{ url: clean, type, quality: ext.toUpperCase(), label: `Direct ${ext.toUpperCase()}` }] } };
    }
  } catch (_) {}

  const platform = detectPlatform(clean);

  // Prefer yt-dlp for Instagram: it exposes the actual formats/qualities and
  // avoids relying on one third-party HTML downloader.
  if (platform === 'instagram') {
    try { return await resolveInstagram(clean); }
    catch (ytError) {
      try {
        const viaScrapr = await resolveWithScrapr(clean);
        if (viaScrapr) return viaScrapr;
      } catch (_) {}

      try {
        return await resolveInstagramEmbed(clean);
      } catch (embedError) {
        throw new Error(
          `Instagram gagal di semua resolver: ${embedError.message || ytError.message || 'media tidak ditemukan'}`
        );
      }
    }
  }

  const viaScrapr = await resolveWithScrapr(clean);
  if (viaScrapr) return viaScrapr;

  // Keep the known-good legacy TikTok resolver as a safety net.
  if (platform === 'tiktok') return scrape(clean);
  throw new Error(`Resolver ${platform === 'unknown' ? 'platform ini' : platform} sedang tidak tersedia.`);
}

for (const path of ['/api/tiktok', '/api/resolve']) {
  app.post(path, async (q, s) => {
    try {
      const result = await resolveUniversal(q.body?.url);
      s.status(result.status ? 200 : 502).json(result);
    } catch (e) {
      s.status(502).json({ status: false, message: e.message || 'Resolver gagal.' });
    }
  });
  app.get(path, async (q, s) => {
    try {
      const result = await resolveUniversal(q.query?.url);
      s.status(result.status ? 200 : 502).json(result);
    } catch (e) {
      s.status(502).json({ status: false, message: e.message || 'Resolver gagal.' });
    }
  });
}

app.get('/api/instagram/resolve', async (q, s) => {
  try {
    const url = String(q.query.url || '').trim();
    if (!validInstagramUrl(url)) return s.status(400).json({ status: false, message: 'URL Instagram tidak valid.' });
    // Dedicated Instagram route deliberately uses yt-dlp first. Scrapr is a
    // fallback if yt-dlp cannot resolve a public post/reel.
    try {
      return s.json(await resolveInstagram(url));
    } catch (ytError) {
      try {
        const viaScrapr = await resolveWithScrapr(url);
        if (viaScrapr) return s.json(viaScrapr);
      } catch (_) {}

      return s.json(await resolveInstagramEmbed(url));
    }
  } catch (e) {
    s.status(502).json({ status: false, message: e.message });
  }
});

app.listen(PORT, '0.0.0.0', () => console.log(`NzTools API running on ${PORT}`));
