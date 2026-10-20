// Injected into instagram.com (main frame, at document end) by ReelsWebController.
//
// Everything that depends on Instagram's web markup lives in this file. When
// Instagram changes its site and next-reel / nav hiding stops working, this is
// the file to tune. Use `window.__tindeq.diagnose()` from Safari Web Inspector
// (Develop → <device> → instagram.com) to see what the script is finding.
//
// The native side prepends `window.__tindeqConfig = {...}` with the route
// allow-list from InstagramRoutes.swift so both sides agree on what is allowed.
(function () {
  'use strict';
  if (window.__tindeq) return;

  const config = window.__tindeqConfig || {
    reelsSegments: ['reels', 'reel'],
    authSegments: ['accounts', 'challenge'],
    authHostSuffixes: ['facebook.com'],
  };

  let locked = false;
  let handsFree = false;
  const pausedByUs = new WeakSet();

  function post(message) {
    try {
      window.webkit.messageHandlers.tindeq.postMessage(message);
    } catch (_) {
      // Not running inside the app (e.g. pasted into a desktop browser for testing).
    }
  }

  // ---------------------------------------------------------------------------
  // Route policy (reels only)
  // ---------------------------------------------------------------------------

  function firstSegment(path) {
    return path.split('/').filter(Boolean)[0] || '';
  }

  function isReelsPath(path) {
    return config.reelsSegments.indexOf(firstSegment(path)) !== -1;
  }

  function hostMatches(host, suffix) {
    return host === suffix || host.endsWith('.' + suffix);
  }

  function isAllowedHref(href) {
    let url;
    try {
      url = new URL(href, location.href);
    } catch (_) {
      return false;
    }
    if (url.protocol !== 'https:' && url.protocol !== 'http:') return false;
    if (config.authHostSuffixes.some(function (s) { return hostMatches(url.hostname, s); })) {
      return true;
    }
    if (!hostMatches(url.hostname, 'instagram.com') || url.hostname === 'l.instagram.com') {
      return false;
    }
    return isReelsPath(url.pathname) || config.authSegments.indexOf(firstSegment(url.pathname)) !== -1;
  }

  // Swallow taps on links that would leave Reels (profiles, explore, DMs, external
  // links). The native side also enforces this on navigation as a backstop, but
  // stopping it here keeps the user's place in the feed.
  document.addEventListener('click', function (event) {
    const target = event.target;
    const anchor = target && target.closest ? target.closest('a[href]') : null;
    if (!anchor) return;
    if (isAllowedHref(anchor.getAttribute('href'))) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    post({ type: 'blockedLink', href: anchor.href });
  }, true);

  // ---------------------------------------------------------------------------
  // Hide Instagram chrome that leads out of Reels (bottom tab bar, app banners)
  // ---------------------------------------------------------------------------

  const MAX_BAR_HEIGHT_RATIO = 0.25;
  const BANNER_TEXT = /\b(open app|use the app|open instagram|get the app)\b/i;

  function smallFixedAncestor(el) {
    const maxHeight = window.innerHeight * MAX_BAR_HEIGHT_RATIO;
    for (let node = el; node && node !== document.body; node = node.parentElement) {
      const position = getComputedStyle(node).position;
      if (position === 'fixed' || position === 'sticky') {
        // Never hide something big: the reels feed itself may be fixed full-screen.
        return node.getBoundingClientRect().height <= maxHeight ? node : null;
      }
    }
    return null;
  }

  function hide(node) {
    if (!node || node.dataset.tindeqHidden) return;
    node.dataset.tindeqHidden = '1';
    node.style.setProperty('display', 'none', 'important');
  }

  function hideChrome() {
    if (!isReelsPath(location.pathname)) return;
    const anchors = document.querySelectorAll('a[href]');
    for (let i = 0; i < anchors.length; i++) {
      const anchor = anchors[i];
      if (isAllowedHref(anchor.getAttribute('href'))) continue;
      const bar = smallFixedAncestor(anchor);
      // Only hide bars that hold several out-of-reels links (a nav bar), not a
      // single username link overlaid on a reel.
      if (bar && bar.querySelectorAll('a[href]').length >= 3) hide(bar);
    }
    // Walk text nodes rather than elements: far cheaper on Instagram's large DOM.
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const text = node.nodeValue;
      if (!text || text.length > 40 || !BANNER_TEXT.test(text)) continue;
      hide(smallFixedAncestor(node.parentElement));
    }
  }

  let chromeQueued = false;
  function queueHideChrome() {
    if (chromeQueued) return;
    chromeQueued = true;
    setTimeout(function () {
      chromeQueued = false;
      hideChrome();
    }, 300);
  }

  new MutationObserver(queueHideChrome).observe(document.documentElement, {
    childList: true,
    subtree: true,
  });

  // ---------------------------------------------------------------------------
  // Finding the current reel and its scroll container
  // ---------------------------------------------------------------------------

  function sizedVideos() {
    const result = [];
    const videos = document.querySelectorAll('video');
    for (let i = 0; i < videos.length; i++) {
      const rect = videos[i].getBoundingClientRect();
      if (rect.width > 50 && rect.height > 50) result.push({ video: videos[i], rect: rect });
    }
    return result;
  }

  function currentReel() {
    const viewportHeight = window.innerHeight;
    let best = null;
    let bestOverlap = 0;
    const videos = sizedVideos();
    for (let i = 0; i < videos.length; i++) {
      const r = videos[i].rect;
      const overlap = Math.min(r.bottom, viewportHeight) - Math.max(r.top, 0);
      if (overlap > bestOverlap) {
        best = videos[i];
        bestOverlap = overlap;
      }
    }
    return best;
  }

  function scrollContainerFor(el) {
    for (let node = el && el.parentElement; node; node = node.parentElement) {
      const overflowY = getComputedStyle(node).overflowY;
      if ((overflowY === 'auto' || overflowY === 'scroll') && node.scrollHeight > node.clientHeight + 1) {
        return node;
      }
    }
    return document.scrollingElement || document.documentElement;
  }

  function isDocumentScroller(el) {
    return el === document.scrollingElement || el === document.documentElement || el === document.body;
  }

  function wait(ms) {
    return new Promise(function (resolve) { setTimeout(resolve, ms); });
  }

  function describe(el) {
    if (!el) return 'none';
    if (isDocumentScroller(el)) return 'document';
    const cls = typeof el.className === 'string' ? el.className.split(/\s+/).slice(0, 2).join('.') : '';
    return el.tagName.toLowerCase() + (cls ? '.' + cls : '');
  }

  // ---------------------------------------------------------------------------
  // Public API (called from Swift)
  // ---------------------------------------------------------------------------

  // Scrolls to the next reel. Resolves with a short diagnostic string that the
  // app logs, e.g. "ok:container:div.x1abc", "ok:fallback-instant", "stuck".
  async function nextReel() {
    if (!isReelsPath(location.pathname)) return 'skip:not-reels';
    const current = currentReel();
    const scroller = current ? scrollContainerFor(current.video) : (document.scrollingElement || document.documentElement);
    const docScroll = isDocumentScroller(scroller);
    const step = docScroll ? window.innerHeight : scroller.clientHeight;

    // Prefer the exact distance to the next video below the current one; that
    // is one reel's height even when the container has padding or headers.
    let delta = step;
    if (current) {
      const below = sizedVideos()
        .filter(function (v) { return v.rect.top > current.rect.top + current.rect.height * 0.5; })
        .sort(function (a, b) { return a.rect.top - b.rect.top; })[0];
      if (below && below.rect.top - current.rect.top > 0) delta = below.rect.top - current.rect.top;
    }

    const readTop = function () { return docScroll ? window.scrollY : scroller.scrollTop; };
    const before = readTop();

    if (docScroll) window.scrollBy({ top: delta, behavior: 'smooth' });
    else scroller.scrollBy({ top: delta, behavior: 'smooth' });
    await wait(450);
    if (Math.abs(readTop() - before) > 4) return 'ok:' + (docScroll ? 'document' : 'container:' + describe(scroller));

    // Smooth scrolling can be swallowed by scroll-snap or an in-flight
    // animation; try an instant jump.
    if (docScroll) window.scrollTo(0, before + delta);
    else scroller.scrollTop = before + delta;
    await wait(150);
    if (Math.abs(readTop() - before) > 4) return 'ok:fallback-instant';

    // Last resort: keyboard navigation (desktop-style reels viewer).
    const key = { key: 'ArrowDown', code: 'ArrowDown', keyCode: 40, bubbles: true };
    (document.activeElement || document.body).dispatchEvent(new KeyboardEvent('keydown', key));
    await wait(300);
    if (Math.abs(readTop() - before) > 4) return 'ok:keyboard';
    return 'stuck:' + describe(scroller) + ':videos=' + sizedVideos().length;
  }

  // Locked: pause everything and keep it paused. Unlocked: resume only what we paused.
  function setLocked(value) {
    locked = !!value;
    const videos = document.querySelectorAll('video');
    if (locked) {
      for (let i = 0; i < videos.length; i++) {
        if (!videos[i].paused) {
          pausedByUs.add(videos[i]);
          videos[i].pause();
        }
      }
      return;
    }
    const current = currentReel();
    if (current && current.video.paused && pausedByUs.has(current.video)) {
      const playing = current.video.play();
      if (playing && playing.catch) playing.catch(function () {});
    }
  }

  document.addEventListener('play', function (event) {
    if (locked && event.target instanceof HTMLVideoElement) {
      pausedByUs.add(event.target);
      event.target.pause();
    }
  }, true);

  // Hands-free: block finger scrolling on reels (taps still work). Programmatic
  // scrolling from nextReel() is unaffected.
  function setHandsFree(value) {
    handsFree = !!value;
  }

  window.addEventListener('touchmove', function (event) {
    if (handsFree && isReelsPath(location.pathname)) event.preventDefault();
  }, { passive: false, capture: true });

  function diagnose() {
    const current = currentReel();
    const scroller = current ? scrollContainerFor(current.video) : null;
    return JSON.stringify({
      path: location.pathname,
      locked: locked,
      handsFree: handsFree,
      videos: document.querySelectorAll('video').length,
      sizedVideos: sizedVideos().length,
      current: current ? { top: Math.round(current.rect.top), height: Math.round(current.rect.height) } : null,
      scroller: scroller ? {
        el: describe(scroller),
        scrollTop: Math.round(isDocumentScroller(scroller) ? window.scrollY : scroller.scrollTop),
        clientHeight: scroller.clientHeight,
        scrollHeight: scroller.scrollHeight,
      } : null,
      hiddenChrome: document.querySelectorAll('[data-tindeq-hidden]').length,
      viewport: { w: window.innerWidth, h: window.innerHeight },
    });
  }

  window.__tindeq = {
    nextReel: nextReel,
    setLocked: setLocked,
    setHandsFree: setHandsFree,
    diagnose: diagnose,
  };

  queueHideChrome();
  post({ type: 'ready', path: location.pathname });
})();
