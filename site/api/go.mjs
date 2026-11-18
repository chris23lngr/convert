// /download and /github (rewrites in vercel.json): count the click on the
// server, then send the visitor on. Works with JavaScript off and can't be
// stripped by a content blocker, since it is an ordinary link to this site.
import { campaignOf, forward } from './_pulse.mjs';

const TARGETS = {
  download: { kind: 'download', url: 'https://github.com/newtonstudios/convert/releases/latest/download/Convert.zip' },
  github: { kind: 'repo', url: 'https://github.com/newtonstudios/convert' },
};

export default async function handler(req, res) {
  const to = new URL(req.url, 'https://convert.newtonbuilds.dev').searchParams.get('to');
  const target = TARGETS[to] || TARGETS.github;
  // Same-site navigation keeps the full page URL as the referer, campaign included.
  const page = req.headers.referer || '';
  await forward(req, { kind: target.kind, path: target.url, ...campaignOf(page) });
  res.statusCode = 302;
  res.setHeader('Location', target.url);
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Robots-Tag', 'noindex');
  res.end();
}
