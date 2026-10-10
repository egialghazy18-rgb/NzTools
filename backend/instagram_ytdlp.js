const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const jobs = new Map();
const JOB_TTL = 30 * 60 * 1000;

function validInstagramUrl(url) {
  return /^https?:\/\/(?:www\.)?instagram\.com\/(?:p|reel|reels|tv|stories)\/[A-Za-z0-9_.-]+/i.test(String(url || '').trim());
}

function run(command, args, timeoutMs = 180000) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    let settled = false;

    const timer = setTimeout(() => {
      // Restricted hosts may reject process signals.
      let killError = null;
      try {
        if (child.exitCode === null && child.signalCode === null) {
          child.kill('SIGKILL');
        }
      } catch (err) {
        killError = err;
      }
      const suffix = killError
        ? `; kill failed: ${killError.message}`
        : '';
      finish(new Error(`${command} timeout${suffix}`));
    }, timeoutMs);

    function finish(err, output) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      err ? reject(err) : resolve(output);
    }

    child.stdout.on('data', d => stdout += d.toString());
    child.stderr.on('data', d => {
      stderr += d.toString();
      if (stderr.length > 12000) stderr = stderr.slice(-12000);
    });
    child.on('error', err => finish(err));
    child.on('close', code => {
      if (code !== 0) {
        finish(new Error(stderr.trim().split('\n').slice(-4).join(' ') || `${command} exited ${code}`));
      } else {
        finish(null, stdout.trim());
      }
    });
  });
}

function authorName(value) {
  if (typeof value === 'string' && value.trim() && value !== '[object Object]') {
    return value.trim().replace(/^@+/, '');
  }
  if (value && typeof value === 'object') {
    for (const key of ['username', 'user_name', 'name', 'full_name']) {
      if (typeof value[key] === 'string' && value[key].trim()) {
        return value[key].trim().replace(/^@+/, '');
      }
    }
  }
  return 'Instagram';
}

function cleanOldJobs() {
  const now = Date.now();
  for (const [id, job] of jobs) {
    if (now - job.createdAt > JOB_TTL) {
      jobs.delete(id);
      fs.rm(job.dir, { recursive: true, force: true }, () => {});
    }
  }
}

let instagramResolveBusy = false;

async function resolveInstagram(url) {
  if (instagramResolveBusy) {
    throw new Error(
      'Resolver Instagram sedang memproses unduhan lain. Coba lagi sebentar.'
    );
  }

  instagramResolveBusy = true;
  try {
    return await resolveInstagramJob(url);
  } finally {
    instagramResolveBusy = false;
  }
}

async function resolveInstagramJob(url) {
  if (!validInstagramUrl(url)) throw new Error('URL Instagram tidak valid.');

  const clean = String(url).trim().split('#')[0];
  const raw = await run('yt-dlp', [
    '--dump-single-json', '--no-playlist', '--no-warnings', clean
  ], 90000);
  const info = JSON.parse(raw);

  if (info._type === 'playlist' || info.entries) {
    throw new Error('URL harus mengarah ke satu postingan Instagram.');
  }

  const id = crypto.randomBytes(16).toString('hex');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'nztools-'));
  const videoPath = path.join(dir, 'media.mp4');
  const mp3Path = path.join(dir, 'audio.mp3');

  try {
    await run('yt-dlp', [
      '--no-playlist',
      '--no-warnings',
      '--no-part',
      '-f', 'bestvideo[ext=mp4]+bestaudio/best[ext=mp4]/best',
      '--merge-output-format', 'mp4',
      '-o', videoPath,
      clean
    ], 240000);

    if (!fs.existsSync(videoPath) || fs.statSync(videoPath).size === 0) {
      throw new Error('File MP4 gagal dibuat.');
    }

    const job = { dir, videoPath, mp3Path, createdAt: Date.now() };
    jobs.set(id, job);
    cleanOldJobs();

    const downloads = [{
      url: `/api/instagram/file/${id}/video`,
      quality: `${info.height || info.width || '?'}p`,
      type: 'video',
      label: 'Download MP4',
      width: info.width || null,
      height: info.height || null
    }];

    try {
      await run('ffmpeg', [
        '-y', '-i', videoPath, '-vn',
        '-codec:a', 'libmp3lame', '-q:a', '2',
        mp3Path
      ], 180000);

      if (fs.existsSync(mp3Path) && fs.statSync(mp3Path).size > 0) {
        downloads.push({
          url: `/api/instagram/file/${id}/audio`,
          quality: 'MP3',
          type: 'music',
          label: 'Download MP3',
          audioOnly: true
        });
      }
    } catch (err) {
      console.error('Konversi MP3 gagal:', err.message);
    }

    return {
      status: true,
      result: {
        title: info.title || 'Instagram Content',
        author: authorName(info.uploader || info.channel || info.creator),
        thumbnail: info.thumbnail || '',
        type: info._type === 'image' ? 'photo' : 'video',
        platform: 'Instagram',
        duration: info.duration || null,
        source_url: clean,
        downloads
      }
    };
  } catch (err) {
    fs.rm(dir, { recursive: true, force: true }, () => {});
    throw err;
  }
}

function getInstagramFile(id, kind) {
  if (!/^[a-f0-9]{32}$/.test(String(id || ''))) return null;
  const job = jobs.get(id);
  if (!job || Date.now() - job.createdAt > JOB_TTL) return null;

  if (kind === 'video') {
    return { path: job.videoPath, name: 'NzTools-Instagram.mp4', mime: 'video/mp4' };
  }
  if (kind === 'audio' && fs.existsSync(job.mp3Path)) {
    return { path: job.mp3Path, name: 'NzTools-Instagram.mp3', mime: 'audio/mpeg' };
  }
  return null;
}

module.exports = {
  resolveInstagram,
  validInstagramUrl,
  getInstagramFile
};
