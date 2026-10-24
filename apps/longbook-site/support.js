// Support opens the chat.sh messenger only when someone asks for it, so a visitor who never
// clicks Support sends nothing to chat.sh and keeps nothing from it in this browser.
(function () {
  var SITE = 'c9a8a115-6b20-4c4f-93d4-e281c327fc99';
  var state = 'idle';

  // A blocked or failed script falls back to the Support page, which carries the email address.
  function failed() {
    state = 'idle';
    var note = document.getElementById('support-failed');
    if (note) note.hidden = false;
    else location.href = '/support/';
  }

  function open() {
    if (state === 'ready') { window.chatSh.open(); return; }
    if (state === 'loading') return;
    state = 'loading';
    var s = document.createElement('script');
    s.src = 'https://chat.sh/widget.js';
    s.async = true;
    s.setAttribute('data-site', SITE);
    s.setAttribute('data-launcher', 'none');
    s.onload = function () {
      if (!window.chatSh) { failed(); return; }
      state = 'ready';
      window.chatSh.open();
    };
    s.onerror = failed;
    document.body.appendChild(s);
  }

  document.addEventListener('click', function (e) {
    var a = e.target.closest ? e.target.closest('[data-support]') : null;
    if (!a || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    open();
  });
})();
