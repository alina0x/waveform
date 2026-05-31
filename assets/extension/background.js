// Waveform Bridge — Tier 3 fallback for the desktop app's login dialog.
//
// Posts the SoundCloud oauth_token cookie to the app's loopback so you don't
// have to copy/paste it. The app validates the token against /me before
// signing in — a guest/expired cookie is harmless: worst case is silence.
//
// To watch this script live: brave://extensions → "Inspect views: service
// worker" under "Waveform Bridge". Logs appear in that DevTools console.

const LOOPBACK = "http://127.0.0.1:47189/token";
const COOKIE_NAME = "oauth_token";

// SoundCloud has historically used a couple of cookie scopes for the token
// (.soundcloud.com vs soundcloud.com, https vs http). chrome.cookies.get
// matches the URL against the cookie's domain rules; try multiple URLs so
// we don't miss a host-only cookie on a different scope.
const COOKIE_URLS = [
  "https://soundcloud.com/",
  "https://www.soundcloud.com/",
  "https://api.soundcloud.com/",
  "https://api-v2.soundcloud.com/",
];

const LOG_PREFIX = "[waveform-bridge]";
function log(...args) {
  console.log(LOG_PREFIX, ...args);
}
function warn(...args) {
  console.warn(LOG_PREFIX, ...args);
}

async function readToken() {
  // First try direct lookups by URL.
  for (const url of COOKIE_URLS) {
    try {
      const cookie = await chrome.cookies.get({ url, name: COOKIE_NAME });
      if (cookie && cookie.value) {
        log("cookies.get hit:", url, "domain=" + cookie.domain);
        try {
          return decodeURIComponent(cookie.value);
        } catch {
          return cookie.value;
        }
      }
    } catch (e) {
      warn("cookies.get failed for", url, e);
    }
  }
  // Fallback: scan everything on the soundcloud domain.
  try {
    const all = await chrome.cookies.getAll({ domain: ".soundcloud.com" });
    log("cookies.getAll(.soundcloud.com) →", all.length, "cookies");
    const hit = all.find((c) => c.name === COOKIE_NAME && c.value);
    if (hit) {
      log("getAll hit: domain=" + hit.domain);
      try {
        return decodeURIComponent(hit.value);
      } catch {
        return hit.value;
      }
    }
  } catch (e) {
    warn("cookies.getAll failed", e);
  }
  return null;
}

async function push(reason) {
  log("push(" + reason + ") — looking up cookie…");
  const token = await readToken();
  if (!token) {
    log("no oauth_token cookie found yet");
    // Also POST a no-token diagnostic so the desktop app can see we're alive.
    try {
      await fetch(LOOPBACK, {
        method: "POST",
        headers: { "Content-Type": "text/plain" },
        body: JSON.stringify({ alive: true, reason, found: false }),
      });
      log("diagnostic POST OK (alive=true, no token)");
    } catch (e) {
      warn("diagnostic POST failed", e);
    }
    return;
  }
  log("posting token (len=" + token.length + ") reason=" + reason);
  try {
    const res = await fetch(LOOPBACK, {
      method: "POST",
      headers: { "Content-Type": "text/plain" },
      body: JSON.stringify({ token, reason }),
    });
    log("POST result:", res.status, res.statusText);
  } catch (e) {
    warn("POST failed (loopback down? wrong port?):", e);
  }
}

// Fire on every lifecycle event we get — install, browser start, and any
// cookie change for soundcloud.com.
chrome.runtime.onInstalled.addListener((details) => {
  log("onInstalled", details);
  push("installed");
});

chrome.runtime.onStartup.addListener(() => {
  log("onStartup");
  push("startup");
});

chrome.cookies.onChanged.addListener((change) => {
  if (change.cookie.name !== COOKIE_NAME) return;
  if (!change.cookie.domain.includes("soundcloud.com")) return;
  if (change.removed) {
    log("oauth_token removed (sign-out?)");
    return;
  }
  log("oauth_token changed (cause=" + change.cause + ")");
  push("changed");
});

// Also try once when the SW spins up — covers the case where install fired
// before our handler registered.
push("worker-start");

log("service worker ready");
