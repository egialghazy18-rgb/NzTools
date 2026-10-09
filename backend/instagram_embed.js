'use strict';

const axios = require('axios');
const cheerio = require('cheerio');

function validInstagramUrl(value) {
  try {
    const u = new URL(value);
    return /(^|\.)instagram\.com$/i.test(u.hostname) &&
      /^\/(p|reel|reels|tv)\/[A-Za-z0-9_-]+\/?/i.test(u.pathname);
  } catch (_) {
    return false;
  }
}

async function resolveInstagramEmbed(input) {
  if (!validInstagramUrl(input)) {
    throw new Error('URL postingan Instagram tidak valid.');
  }

  const u = new URL(input);
  const match = u.pathname.match(/^\/(p|reel|reels|tv)\/([A-Za-z0-9_-]+)/i);
  const shortcode = match[2];
  const embedUrl =
    `https://www.instagram.com/${match[1]}/${shortcode}/embed/captioned/`;

  const response = await axios.get(embedUrl, {
    timeout: 15000,
    headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml',
      'Referer': 'https://www.instagram.com/'
    }
  });

  const html = response.data;
  const $ = cheerio.load(html);

  const thumbnail =
    $('meta[property="og:image"]').attr('content') || '';
  const title =
    $('meta[property="og:title"]').attr('content') ||
    $('title').text().trim() ||
    'Instagram Media';

  const video =
    $('meta[property="og:video"]').attr('content') ||
    $('meta[property="og:video:secure_url"]').attr('content') || '';

  const image =
    $('meta[property="og:image"]').attr('content') || '';

  const mediaUrl = video || image;

  if (!mediaUrl) {
    throw new Error(
      'Media tidak ditemukan. Instagram mungkin membatasi akses atau postingan bersifat privat.'
    );
  }

  const isVideo = Boolean(video);

  return {
    status: true,
    result: {
      title,
      author: 'Instagram',
      thumbnail,
      type: isVideo ? 'video' : 'photo',
      platform: 'Instagram',
      source_url: input,
      downloads: [{
        url: mediaUrl,
        type: isVideo ? 'video' : 'photo',
        quality: 'Original',
        label: isVideo ? 'Instagram Video' : 'Instagram Photo'
      }]
    }
  };
}

module.exports = { resolveInstagramEmbed, validInstagramUrl };
