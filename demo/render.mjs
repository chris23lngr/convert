// Renders scene.html frame by frame (deterministic time) and pipes PNGs into ffmpeg.
//   node render.mjs              → out/convert-demo.mp4  (1920x1080, 60 fps, 2-sample motion blur)
//   node render.mjs --preview    → out/preview.mp4       (960x540, 30 fps, no blur)
//   node render.mjs --stills 1.6,3.3,6.6   → out/still-<t>.png
import { chromium } from 'playwright';
import { spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const preview = args.includes('--preview');
const stillsArg = args.includes('--stills') ? args[args.indexOf('--stills') + 1] : null;
const loop = args.includes('--loop');            // light background, no end card, loops
const crf = args.includes('--crf') ? args[args.indexOf('--crf') + 1] : null;
mkdirSync(path.join(here, 'out'), { recursive: true });

const browser = await chromium.launch({ channel: 'chrome' });
const page = await browser.newPage({
  viewport: { width: 1920, height: 1080 },
  deviceScaleFactor: preview ? 0.5 : 1,
});
await page.goto('file://' + path.join(here, 'scene.html') + (loop ? '?loop=1&bg=light' : ''));
await page.evaluate(() => window.ready);
const duration = await page.evaluate(() => window.DURATION);

async function shot(t) {
  await page.evaluate(async (t) => {
    window.render(t);
    await Promise.all([...document.images].map(i => i.decode().catch(() => {})));
  }, t);
  return page.screenshot({ type: 'png' });
}

if (stillsArg) {
  for (const t of stillsArg.split(',').map(Number)) {
    const buf = await shot(t);
    const fs = await import('node:fs');
    fs.writeFileSync(path.join(here, 'out', `still${loop ? '-loop' : ''}-${t.toFixed(2)}.png`), buf);
  }
  await browser.close();
  process.exit(0);
}

const fps = preview ? 30 : 60;
const sub = args.includes('--blur') ? 2 : 1;  // crisp by default; two samples ghost the fast cursor
const out = path.join(here, 'out', preview ? 'preview.mp4' : loop ? 'convert-loop.mp4' : 'convert-demo.mp4');
const vf = sub > 1
  ? `tmix=frames=${sub},select='not(mod(n+1\\,${sub}))',setpts=N/${fps}/TB`
  : 'null';
const ff = spawn('ffmpeg', [
  '-y', '-v', 'error',
  '-f', 'image2pipe', '-c:v', 'png', '-framerate', String(fps * sub), '-i', '-',
  '-vf', vf, '-r', String(fps),
  '-c:v', 'libx264', '-preset', preview ? 'veryfast' : 'slow', '-crf', crf ?? (preview ? '22' : '14'),
  '-pix_fmt', 'yuv420p', '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709',
  '-movflags', '+faststart', out,
], { stdio: ['pipe', 'inherit', 'inherit'] });

const frames = Math.round(duration * fps);
const started = Date.now();
for (let f = 0; f < frames; f++) {
  for (let s = 0; s < sub; s++) {
    const t = (f + s / (sub * 2)) / fps;        // samples within the first half of the frame
    const buf = await shot(t);
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
  }
  if (f % 60 === 0) process.stdout.write(`\rframe ${f}/${frames}  ${((Date.now() - started) / 1000).toFixed(0)}s`);
}
ff.stdin.end();
await new Promise(r => ff.on('close', r));
await browser.close();
console.log(`\nwrote ${out}`);
