// Page views, sent by the page itself to this site's own address (so there
// is no third-party request to block), and clicks on links that leave the
// site other than /download and /github. Forwarded from here, server-side.
//
//   POST (sendBeacon) { kind: "pageview" | "outbound", path, referrer?, page? }
//   GET  /api/pulse    the <noscript> image: a page view without JavaScript
import { campaignOf, forward } from './_pulse.mjs';

const GIF = Buffer.from('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7', 'base64');

async function readJson(req) {
  if (req.body && typeof req.body === 'object' && !Buffer.isBuffer(req.body)) return req.body;
  let text = typeof req.body === 'string' ? req.body : Buffer.isBuffer(req.body) ? req.body.toString('utf8') : '';
  if (!text) {
    for await (const chunk of req) {
      text += chunk;
      if (text.length > 4096) return null;
    }
  }
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

const str = (v, max) => (typeof v === 'string' && v ? v.slice(0, max) : undefined);

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Robots-Tag', 'noindex');

  if (req.method === 'GET') {
    await forward(req, { kind: 'pageview', path: '/', referrer: undefined, ...campaignOf(req.headers.referer || '') });
    res.setHeader('Content-Type', 'image/gif');
    res.end(GIF);
    return;
  }
  if (req.method !== 'POST') {
    res.statusCode = 405;
    res.end();
    return;
  }

  const b = await readJson(req);
  const kind = b && (b.kind === 'pageview' || b.kind === 'outbound') ? b.kind : null;
  const path = b && str(b.path, 300);
  if (kind && path) {
    await forward(req, { kind, path, referrer: str(b.referrer, 1000), ...campaignOf(str(b.page, 1000) || '') });
  }
  res.statusCode = 204;
  res.end();
}
