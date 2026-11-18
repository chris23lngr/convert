// Forwards one visit to the Newton Studios dashboard, signed with PULSE_SECRET.
// Files starting with "_" are not deployed as functions; this is shared by
// pulse.mjs (page views) and go.mjs (the /download and /github redirects).
//
// The visitor's IP and user agent are passed on so the dashboard can tell
// visitors apart for the day and guess the device. It keeps neither: it
// stores a hash that changes every day. Nothing is stored in the browser.
import { createHmac } from 'node:crypto';

const SITE = 'convert';
const ENDPOINT = process.env.PULSE_ENDPOINT || 'https://admin.newton-studios.com/api/pulse';

const header = (req, name) => {
  const v = req.headers[name];
  return (Array.isArray(v) ? v[0] : v) || '';
};

/** The visitor as the edge saw them. Vercel sets these; a client can't. */
export function visitorOf(req) {
  const ip = header(req, 'x-real-ip') || header(req, 'x-forwarded-for').split(',')[0].trim() || 'unknown';
  return {
    ip: ip.slice(0, 64),
    ua: header(req, 'user-agent').slice(0, 512),
    country: header(req, 'x-vercel-ip-country').slice(0, 8) || undefined,
  };
}

/** utm_source (or ref) and utm_campaign from a page URL, when there is one. */
export function campaignOf(pageUrl) {
  try {
    const q = new URL(pageUrl).searchParams;
    return {
      utm_source: (q.get('utm_source') || q.get('ref') || '').slice(0, 64) || undefined,
      utm_campaign: (q.get('utm_campaign') || '').slice(0, 100) || undefined,
    };
  } catch {
    return {};
  }
}

/** Never throws and never takes long: a lost count must not cost a visitor anything. */
export async function forward(req, event) {
  const secret = process.env.PULSE_SECRET;
  if (!secret || req.method === 'HEAD') return;
  const body = JSON.stringify({ site: SITE, ...event, visitor: visitorOf(req) });
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = createHmac('sha256', secret).update(`${timestamp}.${body}`).digest('hex');
  try {
    await fetch(ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-pulse-timestamp': timestamp, 'x-pulse-signature': signature },
      body,
      signal: AbortSignal.timeout(1500),
    });
  } catch {
    // The dashboard being slow or down is not the visitor's problem.
  }
}
