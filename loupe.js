/* ============================================================
   Live Loupe — landing interactions
   (QR render, scroll reveal, nav, FAQ, hero switch, Tweaks)
   ============================================================ */
(function () {
  'use strict';

  /* ---------- real QR renderer (qrcode-generator, drawn to canvas) ---------- */
  var QR_URL = 'https://www.instagram.com/thecapturecrafter/';
  function drawQR(canvas, opts) {
    opts = opts || {};
    var qr = qrcode(0, 'M');          // type 0 = auto-size, error-correction level M
    qr.addData(opts.url || QR_URL);
    qr.make();
    var count = qr.getModuleCount();
    var margin = 4;                   // quiet zone (modules) — required for reliable scanning
    var total = count + margin * 2;
    var px = Math.max(1, Math.floor((opts.size || 264) / total));
    var dim = px * total;
    canvas.width = dim; canvas.height = dim;
    var ctx = canvas.getContext('2d');
    ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 0, dim, dim);
    ctx.fillStyle = '#0b0b0d';
    for (var r = 0; r < count; r++) for (var c = 0; c < count; c++) {
      if (qr.isDark(r, c)) ctx.fillRect((c + margin) * px, (r + margin) * px, px, px);
    }
  }
  window.__drawQR = drawQR;
  function renderAllQR() {
    document.querySelectorAll('canvas.qr').forEach(function (c) {
      drawQR(c, { size: c.dataset.size ? +c.dataset.size : 264 });
    });
  }

  /* ---------- nav scroll state ---------- */
  function initNav() {
    var nav = document.querySelector('.nav');
    if (!nav) return;
    var onScroll = function () { nav.classList.toggle('scrolled', window.scrollY > 16); };
    onScroll(); window.addEventListener('scroll', onScroll, { passive: true });
  }

  /* ---------- scroll reveal ---------- */
  function initReveal() {
    var els = document.querySelectorAll('.reveal');
    if (!('IntersectionObserver' in window)) { els.forEach(function (e) { e.classList.add('in'); }); return; }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add('in'); io.unobserve(en.target); }
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -8% 0px' });
    els.forEach(function (e, i) { e.style.transitionDelay = (Math.min(i % 3, 2) * 80) + 'ms'; io.observe(e); });
  }

  /* ---------- FAQ accordion ---------- */
  function initFAQ() {
    document.querySelectorAll('.faq-q').forEach(function (q) {
      q.addEventListener('click', function () {
        var item = q.closest('.faq-item');
        var ans = item.querySelector('.faq-a');
        var open = item.classList.contains('open');
        if (open) { item.classList.remove('open'); ans.style.maxHeight = '0px'; }
        else { item.classList.add('open'); ans.style.maxHeight = ans.scrollHeight + 'px'; }
      });
    });
  }

  /* ---------- tweaks (fixed production defaults) ---------- */
  var TWEAKS = { accent: '#0A84FF', heroVariant: 'flow', theme: 'dark' };

  function applyTweaks(t) {
    var root = document.documentElement;
    root.style.setProperty('--accent', t.accent);
    root.setAttribute('data-theme', t.theme);
    var a = document.querySelector('.heroA'), b = document.querySelector('.heroB');
    if (a && b) {
      a.style.display = t.heroVariant === 'split' ? 'grid' : 'none';
      b.style.display = t.heroVariant === 'flow' ? 'block' : 'none';
    }
    // refresh faq heights (theme/spacing may shift)
    document.querySelectorAll('.faq-item.open .faq-a').forEach(function (ans) { ans.style.maxHeight = ans.scrollHeight + 'px'; });
  }

  /* ---------- boot ---------- */
  function boot() {
    applyTweaks(TWEAKS);
    renderAllQR();
    initNav();
    initReveal();
    initFAQ();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
