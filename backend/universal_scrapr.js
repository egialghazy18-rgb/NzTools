'use strict';

let scrapr = null;
try {
  scrapr = require('@coflyn/scrapr');
} catch (_) {
  // The rest of the backend still has legacy resolvers as fallbacks.
}

function hostOf(input) {
  try { return new URL(input).hostname.toLowerCase().replace(/^www\./, ''); }
  catch (_) { return ''; }
}

function detectPlatform(input) {
  const host = hostOf(input);
  if (host.includes('tiktok.com')) return 'tiktok';
  if (host === 'instagram.com' || host.endsWith('.instagram.com')) return 'instagram';
  if (host === 'youtube.com' || host === 'youtu.be' || host.endsWith('.youtube.com')) return 'youtube';
  if (host === 'facebook.com' || host.endsWith('.facebook.com') || host === 'fb.watch') return 'facebook';
  if (host === 'x.com' || host === 'twitter.com' || host.endsWith('.twitter.com')) return 'twitter';
  if (host === 'pinterest.com' || host.endsWith('.pinterest.com') || host === 'pin.it') return 'pinterest';
  if (host === 'reddit.com' || host.endsWith('.reddit.com')) return 'reddit';
  if (host === 'threads.net' || host.endsWith('.threads.net')) return 'threads';
  if (host === 'soundcloud.com' || host.endsWith('.soundcloud.com')) return 'soundcloud';
  if (host === 'spotify.com' || host.endsWith('.spotify.com')) return 'spotify';
  if (host === 'bilibili.com' || host.endsWith('.bilibili.com') || host === 'b23.tv') return 'bilibili';
  if (host === 'douyin.com' || host.endsWith('.douyin.com')) return 'douyin';
  if (host === 'bandcamp.com' || host.endsWith('.bandcamp.com')) return 'bandcamp';
  if (host === 'pixiv.net' || host.endsWith('.pixiv.net')) return 'pixiv';
  if (host === 'threads.com' || host.endsWith('.threads.com')) return 'threads';
  return 'unknown';
}

const chains = {
  tiktok: ['snaptik', 'tiktokio', 'savetik', 'ssstik', 'tikdownloader'],
  instagram: ['direct', 'indown', 'snapsave', 'snapinsta'],
  youtube: ['ytmp3', 'ytmp3gg'],
  facebook: ['snapsave', 'fdown'],
  twitter: ['direct', 'tweeload', 'tvd', 'savetwt'],
  pinterest: ['direct', 'pindown'],
  reddit: ['rapidsave'],
  threads: ['threadster'],
  soundcloud: ['direct'],
  spotify: ['direct'],
  bilibili: ['direct'],
  douyin: ['direct'],
  bandcamp: ['direct'],
  pixiv: ['direct'],
};

function normalize(platform, response, sourceUrl) {
  if (!response || response.status !== true || !response.result) return null;
  const r = response.result;
  const rawDownloads = Array.isArray(r.downloads) ? r.downloads : [];
  const downloads = rawDownloads.map((d, i) => {
    const item = d && typeof d === 'object' ? d : {};
    const url = String(item.url || item.link || item.download || '').trim();
    if (!url) return null;
    const type0 = String(item.type || '').toLowerCase();
    const quality = String(item.quality || item.resolution || item.label || `media_${i + 1}`);
    const type = type0.includes('photo') || type0.includes('image') ? 'photo'
      : type0.includes('audio') || type0.includes('music') || type0.includes('mp3') ? 'music'
      : 'video';
    return {
      url,
      type,
      quality,
      label: String(item.label || quality || `Download ${type}`),
      width: item.width || null,
      height: item.height || null,
      size: item.size || null,
    };
  }).filter(Boolean);

  if (!downloads.length) return null;
  return {
    status: true,
    result: {
      title: String(r.title || r.caption || `${platform} media`),
      author: (() => {
      const a = r.author || r.uploader || r.username;
      if (typeof a === 'string' && a.trim() && a !== '[object Object]') {
        return a.trim().replace(/^@+/, '');
      }
      if (a && typeof a === 'object') {
        for (const k of ['username', 'user_name', 'name', 'full_name']) {
          if (typeof a[k] === 'string' && a[k].trim()) {
            return a[k].trim().replace(/^@+/, '');
          }
        }
      }
      return platform;
    })(),
      thumbnail: String(r.thumbnail || r.thumb || r.cover || ''),
      type: String(r.type || (downloads.some(x => x.type === 'photo') ? 'photo' : 'video')),
      platform: platform[0].toUpperCase() + platform.slice(1),
      duration: r.duration || null,
      source_url: String(r.source_url || sourceUrl),
      downloads,
    },
  };
}

async function callScrapr(platform, method, url) {
  const group = scrapr && scrapr[platform];
  const fn = group && group[method];
  if (typeof fn !== 'function') return null;
  try {
    const response = await fn(url);
    return normalize(platform, response, url);
  } catch (_) {
    return null;
  }
}

async function resolveWithScrapr(url) {
  if (!scrapr) return null;
  const platform = detectPlatform(url);
  const methods = chains[platform] || [];
  for (const method of methods) {
    const result = await callScrapr(platform, method, url);
    if (result) return { ...result, result: { ...result.result, resolver: `scrapr.${platform}.${method}` } };
  }
  return null;
}

module.exports = { detectPlatform, resolveWithScrapr, normalize };
