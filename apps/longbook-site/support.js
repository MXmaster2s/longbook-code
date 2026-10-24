// Support opens only when someone asks for it: until then this page loads nothing for it.
// A link marked data-support opens the chat; if the chat cannot load, the link goes to /support/.
(function () {
  var state = 'idle';
  document.addEventListener('click', function (e) {
    var a = e.target.closest ? e.target.closest('[data-support]') : null;
    if (!a || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    if (window.lbSupport) { window.lbSupport.open(); return; }
    if (state === 'loading') return;
    state = 'loading';
    var s = document.createElement('script');
    s.src = '/support-chat.js';
    s.async = true;
    s.onload = function () { state = 'idle'; if (window.lbSupport) window.lbSupport.open(); else location.href = '/support/'; };
    s.onerror = function () { state = 'idle'; location.href = '/support/'; };
    document.body.appendChild(s);
  });
})();
