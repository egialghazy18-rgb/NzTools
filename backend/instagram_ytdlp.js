const { spawn } = require('child_process');

function validInstagramUrl(url) {
  return /^https?:\/\/(?:www\.)?instagram\.com\/(?:p|reel|reels|tv|stories)\/[A-Za-z0-9_.-]+/i.test(String(url || '').trim());
}

function runYtDlp(args, timeoutMs = 60000) {
  return new Promise((resolve, reject) => {
    const child = spawn('yt-dlp', args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      reject(new Error('yt-dlp timeout'));
    }, timeoutMs);
    child.stdout.on('data', d => { stdout += d.toString(); });
    child.stderr.on('data', d => { stderr += d.toString(); });
    child.on('error', err => { clearTimeout(timer); reject(err); });
    child.on('close', code => {
      clearTimeout(timer);
      if (code !== 0) return reject(new Error(stderr.trim().split('\n').slice(-3).join(' ') || `yt-dlp exited ${code}`));
      resolve(stdout.trim());
    });
  });
}

async function resolveInstagram(url) {
  if (!validInstagramUrl(url)) throw new Error('URL Instagram tidak valid.');
  const clean = String(url).trim().split('#')[0];
  const raw = await runYtDlp(['--dump-single-json', '--no-playlist', '--no-warnings', clean], 90000);
  const info = JSON.parse(raw);
  const formats = Array.isArray(info.formats) ? info.formats : [];
  const videos = formats
    .filter(f => f && f.url && (f.vcodec && f.vcodec !== 'none'))
    .filter(f => (f.ext === 'mp4' || !f.ext) && Number(f.width || 0) > 0)
    .sort((a,b) => (Number(b.width||0) * Number(b.height||0)) - (Number(a.width||0) * Number(a.height||0)));
  const best = videos[0] || info;
  const audio = formats
    .filter(f => f && f.url && f.acodec && f.acodec !== 'none' && (!f.vcodec || f.vcodec === 'none'))
    .sort((a,b) => Number(b.abr||0) - Number(a.abr||0))[0];

  const downloads = [];
  if (best && best.url) {
    downloads.push({ url: best.url, quality: `${best.width || info.width || '?'}p`, type: 'video', label: 'Download Video', width: best.width || info.width || null, height: best.height || info.height || null });
  }
  if (audio && audio.url) {
    downloads.push({ url: audio.url, quality: `${Math.round(audio.abr || 0)}kbps`, type: 'music', label: 'Download Audio', audioOnly: true });
  }

  if (!downloads.length && info.url) downloads.push({ url: info.url, quality: `${info.width || '?'}p`, type: 'video', label: 'Download Video', width: info.width || null, height: info.height || null });
  if (!downloads.length) throw new Error('yt-dlp tidak menemukan media yang dapat diunduh.');

  return {
    status: true,
    result: {
      title: info.title || 'Instagram Content',
      author: info.uploader || info.channel || 'Instagram',
      thumbnail: info.thumbnail || '',
      type: info._type === 'image' ? 'photo' : 'video',
      platform: 'Instagram',
      duration: info.duration || null,
      source_url: clean,
      downloads,
    },
  };
}

module.exports = { resolveInstagram, validInstagramUrl, runYtDlp };
