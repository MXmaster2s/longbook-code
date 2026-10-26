// Support opens only when someone asks for it: until then this page loads nothing for it.
// A floating Support pill, and any link marked data-support, open the chat; if the chat
// cannot load, they go to /support/.
(function () {
  var state = 'idle';

  function open() {
    if (window.lbSupport) { window.lbSupport.open(); return; }
    if (state === 'loading') return;
    state = 'loading';
    var s = document.createElement('script');
    s.src = '/support-chat.js';
    s.async = true;
    s.onload = function () { state = 'idle'; if (window.lbSupport) window.lbSupport.open(); else location.href = '/support/'; };
    s.onerror = function () { state = 'idle'; location.href = '/support/'; };
    document.body.appendChild(s);
  }

  document.addEventListener('click', function (e) {
    var a = e.target.closest ? e.target.closest('[data-support]') : null;
    if (!a || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    open();
  });

  // The pill, as the Mac app draws it: a brand capsule at the foot of the window, out of
  // the way while the chat is open.
  var style = document.createElement('style');
  style.textContent = [
    '.lbs-pill-fab{position:fixed;right:20px;bottom:20px;z-index:150;display:inline-flex;align-items:center;gap:8px;padding:11px 16px;border:0;border-radius:999px;background:var(--lb-brand);color:var(--lb-on-brand);font:600 14px/1 var(--lb-font-sans);text-decoration:none;cursor:pointer;box-shadow:0 4px 18px rgba(0,0,0,.3);opacity:0;transform:translateY(12px) scale(.96);transition:opacity .28s cubic-bezier(.16,1,.3,1),transform .28s cubic-bezier(.16,1,.3,1),background .15s}',
    '.lbs-pill-fab.on{opacity:1;transform:none}',
    '.lbs-pill-fab:hover{background:var(--lb-brand-hover,var(--lb-brand))}',
    '.lbs-pill-fab:active{transform:scale(.97)}',
    '.lbs-pill-fab:focus-visible{outline:3px solid var(--lb-brand-text);outline-offset:3px}',
    '.lbs-pill-fab.away{opacity:0;transform:translateY(12px) scale(.96);pointer-events:none}',
    '@media (max-width:560px){.lbs-pill-fab{right:16px;bottom:16px;padding:10px 14px}}',
    '@media (prefers-reduced-motion:reduce){.lbs-pill-fab{transition:opacity .15s;transform:none!important}}',
    '@media print{.lbs-pill-fab{display:none}}',
  ].join('\n');
  document.head.appendChild(style);

  var pill = document.createElement('a');
  pill.className = 'lbs-pill-fab';
  pill.href = '/support/';
  pill.setAttribute('data-support', '');
  pill.setAttribute('aria-label', 'Ask longbook Support');
  pill.innerHTML = '<svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M4 3h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H9l-5 4v-4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/></svg><span>Support</span>';

  function place() {
    document.body.appendChild(pill);
    requestAnimationFrame(function () { requestAnimationFrame(function () { pill.classList.add('on'); }); });
  }
  if (document.body) place(); else document.addEventListener('DOMContentLoaded', place);

  window.addEventListener('lbsupport:open', function () { pill.classList.add('away'); });
  window.addEventListener('lbsupport:close', function () { pill.classList.remove('away'); });
})();
