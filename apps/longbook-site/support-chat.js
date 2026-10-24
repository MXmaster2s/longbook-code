// longbook Support on the website: the same AI as the app, answering from the help articles.
// Loaded only when someone opens it; the conversation lives in this page and is gone on reload.
(function () {
  if (window.lbSupport) return;
  var ENDPOINT = 'https://xbrnijgctmovoqbbmgmb.supabase.co/functions/v1/support';
  // Public by design: an anon key is meant to ship in client code.
  var ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhicm5pamdjdG1vdm9xYmJtZ21iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU3NzQ0NDQsImV4cCI6MjEwMTM1MDQ0NH0.ZamrPyf3UmAmbqzzAcce_Ocb1bKNq19wVxTtaC32a-g';
  var OFFER = 'Want me to ask someone on the team to reply to you by email?';
  var GREETING = "Hi, I'm longbook's AI. Ask me anything about longbook. Please don't share amounts, or account or card numbers. If I can't help, someone on the team will reply by email.";
  var STARTERS = ['How do I import a bank statement?', 'How do I connect Claude or ChatGPT?', 'How do I get a refund?', 'Where is my data kept?'];
  var asker = 'web-' + Math.random().toString(36).slice(2) + Date.now().toString(36);
  var turns = [];
  var busy = false;

  var css = [
    '.lbs{position:fixed;right:20px;bottom:20px;z-index:200;width:400px;max-width:calc(100vw - 32px);height:min(640px,calc(100vh - 40px));display:flex;flex-direction:column;background:var(--lb-canvas);color:var(--lb-text-primary);border:1px solid var(--lb-hairline);border-radius:20px;box-shadow:0 24px 60px rgba(0,0,0,.45);overflow:hidden;font-family:var(--lb-font-sans);opacity:0;transform:translateY(16px) scale(.98);transition:opacity .28s cubic-bezier(.16,1,.3,1),transform .28s cubic-bezier(.16,1,.3,1)}',
    '.lbs.on{opacity:1;transform:none}',
    '@media (max-width:560px){.lbs{right:0;bottom:0;width:100vw;max-width:100vw;height:100dvh;border-radius:0;border:0}}',
    '.lbs-bar{display:flex;align-items:center;gap:12px;padding:12px 16px;background:var(--lb-chrome);border-bottom:1px solid var(--lb-hairline)}',
    '.lbs-bar b{display:block;font-size:16px}.lbs-bar small{display:block;color:var(--lb-text-tertiary);font-size:12px}',
    '.lbs-bar .sp{flex:1}.lbs-ib{background:none;border:0;color:var(--lb-text-secondary);cursor:pointer;width:34px;height:34px;border-radius:50%;display:grid;place-items:center}.lbs-ib:hover{background:var(--lb-card);color:var(--lb-text-primary)}',
    '.lbs-av{width:28px;height:28px;flex:none;border-radius:50%;border:1px solid var(--lb-hairline);background:var(--lb-chrome);display:grid;place-items:center;overflow:hidden}.lbs-av img{width:70%;height:70%}',
    '.lbs-av.me{background:color-mix(in srgb,var(--lb-brand) 22%,transparent);color:var(--lb-brand-text)}',
    '.lbs-log{flex:1;overflow-y:auto;padding:16px;display:flex;flex-direction:column;gap:14px;scroll-behavior:smooth}',
    '.lbs-row{display:flex;align-items:flex-end;gap:8px;animation:lbs-in .3s cubic-bezier(.16,1,.3,1)}.lbs-row.me{justify-content:flex-end}',
    '.lbs-col{display:flex;flex-direction:column;gap:6px;max-width:82%}',
    '.lbs-b{padding:9px 12px;border-radius:18px;font-size:15px;line-height:1.5;background:var(--lb-card);border:1px solid var(--lb-hairline);white-space:pre-wrap;overflow-wrap:anywhere}',
    '.lbs-row.me .lbs-b{background:var(--lb-chrome);border-color:transparent}',
    '.lbs-under{margin-left:36px;display:flex;flex-direction:column;gap:6px;animation:lbs-in .3s ease}',
    '.lbs-chip{display:inline-flex;align-items:center;gap:6px;padding:5px 12px;border-radius:999px;font-size:13px;color:var(--lb-brand-text);background:color-mix(in srgb,var(--lb-brand) 12%,transparent);text-decoration:none;max-width:100%;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.lbs-thumbs{display:flex;gap:2px}.lbs-thumbs button{background:none;border:0;cursor:pointer;color:var(--lb-text-tertiary);padding:4px 6px;border-radius:8px}.lbs-thumbs button:hover{color:var(--lb-text-primary)}.lbs-thumbs button[aria-pressed=true]{color:var(--lb-brand-text)}',
    '.lbs-starters{display:flex;flex-direction:column;align-items:flex-end;gap:8px}',
    '.lbs-pill{border:1px solid var(--lb-hairline);background:var(--lb-card);color:var(--lb-text-primary);border-radius:999px;padding:7px 12px;font:inherit;font-size:14px;cursor:pointer;transition:background .15s}.lbs-pill:hover{background:var(--lb-chrome)}',
    '.lbs-pill.pri{background:var(--lb-brand);border-color:var(--lb-brand);color:var(--lb-on-brand)}.lbs-pill:disabled{opacity:.5;cursor:default}',
    '.lbs-card{margin-left:36px;padding:12px;border-radius:18px;background:var(--lb-card);border:1px solid color-mix(in srgb,var(--lb-brand) 35%,transparent);display:flex;flex-direction:column;gap:10px;animation:lbs-in .3s cubic-bezier(.16,1,.3,1)}',
    '.lbs-card p{margin:0;font-size:14px}.lbs-card .note{color:var(--lb-text-tertiary);font-size:12px}.lbs-card .err{color:var(--lb-danger,#db5f75);font-size:12px}',
    '.lbs-card .acts{display:flex;gap:8px;flex-wrap:wrap}',
    '.lbs-in{width:100%;box-sizing:border-box;padding:9px 12px;border-radius:12px;border:1px solid var(--lb-hairline);background:var(--lb-sunken);color:var(--lb-text-primary);font:inherit;font-size:15px}',
    '.lbs-foot{display:flex;gap:8px;align-items:flex-end;padding:12px;background:var(--lb-chrome);border-top:1px solid var(--lb-hairline)}',
    '.lbs-foot textarea{flex:1;resize:none;max-height:120px;overflow-y:auto;scrollbar-width:none;padding:9px 12px;border-radius:18px;border:1px solid var(--lb-hairline);background:var(--lb-card);color:var(--lb-text-primary);font:inherit;font-size:15px;line-height:1.4}',
    '.lbs-send{width:36px;height:36px;border-radius:50%;border:0;background:var(--lb-brand);color:var(--lb-on-brand);cursor:pointer;display:grid;place-items:center;transform:scale(.4);opacity:0;transition:transform .32s cubic-bezier(.34,1.56,.64,1),opacity .2s;pointer-events:none}',
    '.lbs-send.on{transform:none;opacity:1;pointer-events:auto}',
    '.lbs-dots{display:flex;gap:5px;padding:12px}.lbs-dots i{width:7px;height:7px;border-radius:50%;background:var(--lb-text-tertiary);animation:lbs-dot 1.1s infinite ease-in-out}.lbs-dots i:nth-child(2){animation-delay:.15s}.lbs-dots i:nth-child(3){animation-delay:.3s}',
    '@keyframes lbs-in{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:none}}',
    '@keyframes lbs-dot{0%,100%{transform:scale(.7);opacity:.45}50%{transform:scale(1.05);opacity:1}}',
    '@media (prefers-reduced-motion:reduce){.lbs,.lbs-row,.lbs-under,.lbs-card,.lbs-send{animation:none!important;transition:opacity .15s!important;transform:none!important}.lbs-dots i{animation:none}}',
  ].join('\n');

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  function rich(text) {
    var safe = text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    return safe.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  }
  var ICON = {
    person: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="8" r="4"/><path d="M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6"/></svg>',
    close: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>',
    up: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V5M5 12l7-7 7 7"/></svg>',
    yes: '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M7 11v9H4v-9h3zm0 0l4-8c1.7 0 2.6 1.2 2.2 3l-.7 3H19a2 2 0 012 2.3l-1.2 6.4A2 2 0 0117.8 20H7"/></svg>',
    doc: '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 3H6a1 1 0 00-1 1v16a1 1 0 001 1h12a1 1 0 001-1V8l-5-5z"/><path d="M14 3v5h5"/></svg>',
  };
  var NO = ICON.yes.replace('<svg ', '<svg style="transform:scaleY(-1)" ');

  var root, log, input, send, cardEl;

  function supportAvatar() {
    var a = el('span', 'lbs-av');
    a.innerHTML = '<img src="/mark-52.png" alt="">';
    return a;
  }
  function meAvatar() {
    var a = el('span', 'lbs-av me');
    a.innerHTML = ICON.person;
    return a;
  }
  function scrollEnd() { requestAnimationFrame(function () { log.scrollTop = log.scrollHeight; }); }

  function supportRow(html) {
    var row = el('div', 'lbs-row');
    var col = el('div', 'lbs-col');
    var b = el('div', 'lbs-b');
    b.innerHTML = html;
    col.appendChild(b);
    row.appendChild(supportAvatar());
    row.appendChild(col);
    log.appendChild(row);
    scrollEnd();
    return b;
  }
  function meRow(text) {
    var row = el('div', 'lbs-row me');
    var col = el('div', 'lbs-col');
    col.appendChild(el('div', 'lbs-b', text));
    row.appendChild(col);
    row.appendChild(meAvatar());
    log.appendChild(row);
    scrollEnd();
  }

  function post(fields) {
    fields.install_id = asker;
    return fetch(ENDPOINT, {
      method: 'POST',
      headers: { 'content-type': 'application/json', apikey: ANON, authorization: 'Bearer ' + ANON },
      body: JSON.stringify(fields),
    });
  }

  function ask(question) {
    question = question.trim();
    if (!question || busy) return;
    busy = true;
    clearCard();
    var starters = log.querySelector('.lbs-starters');
    if (starters) starters.remove();
    meRow(question);
    turns.push({ role: 'user', content: question });
    input.value = '';
    sync();
    var row = el('div', 'lbs-row');
    var col = el('div', 'lbs-col');
    var dots = el('div', 'lbs-b lbs-dots');
    dots.innerHTML = '<i></i><i></i><i></i>';
    dots.setAttribute('aria-label', 'Writing an answer');
    col.appendChild(dots);
    row.appendChild(supportAvatar());
    row.appendChild(col);
    log.appendChild(row);
    scrollEnd();
    var answer = '';
    var bubble = null;
    post({ messages: turns }).then(function (res) {
      if (!res.ok || !res.body) return res.json().catch(function () { return {}; }).then(function (j) { throw new Error(j.error || "Support couldn't answer just now. Try again in a minute."); });
      var reader = res.body.getReader();
      var decoder = new TextDecoder();
      var pending = '';
      function pump() {
        return reader.read().then(function (r) {
          if (r.done) return;
          pending += decoder.decode(r.value, { stream: true });
          var lines = pending.split('\n');
          pending = lines.pop();
          lines.forEach(function (line) {
            if (line.indexOf('data: ') !== 0) return;
            var e;
            try { e = JSON.parse(line.slice(6)); } catch (x) { return; }
            if (e.error) throw new Error(e.error);
            if (e.text) {
              answer += e.text;
              if (!bubble) { bubble = el('div', 'lbs-b'); dots.replaceWith(bubble); }
              bubble.innerHTML = rich(answer);
              scrollEnd();
            }
            if (e.done) finish(row, answer, e);
          });
          return pump();
        });
      }
      return pump();
    }).catch(function (err) {
      if (!bubble) { bubble = el('div', 'lbs-b'); dots.replaceWith(bubble); }
      bubble.textContent = err.message;
      offer();
    }).then(function () { busy = false; sync(); });
  }

  function finish(row, answer, e) {
    turns.push({ role: 'assistant', content: answer });
    var under = el('div', 'lbs-under');
    (e.articles || []).forEach(function (a) {
      var link = el('a', 'lbs-chip');
      link.href = '/help/' + a.slug + '/';
      link.target = '_blank';
      link.rel = 'noopener';
      link.innerHTML = ICON.doc + '<span></span>';
      link.lastChild.textContent = a.title;
      under.appendChild(link);
    });
    if (e.id) {
      var thumbs = el('div', 'lbs-thumbs');
      [['up', ICON.yes, 'Helpful'], ['down', NO, 'Not helpful']].forEach(function (t) {
        var b = el('button');
        b.type = 'button';
        b.innerHTML = t[1];
        b.setAttribute('aria-label', t[2]);
        b.onclick = function () {
          thumbs.querySelectorAll('button').forEach(function (x) { x.disabled = true; x.setAttribute('aria-pressed', String(x === b)); });
          post({ action: 'feedback', answer_id: e.id, rating: t[0] });
          if (t[0] === 'down') reviewCard();
        };
        thumbs.appendChild(b);
      });
      under.appendChild(thumbs);
    }
    if (under.childNodes.length) row.after(under);
    if (e.email || answer.indexOf('reply to you by email') >= 0) offer();
    scrollEnd();
  }

  function clearCard() { if (cardEl) { cardEl.remove(); cardEl = null; } }
  function card(build) {
    clearCard();
    cardEl = el('div', 'lbs-card');
    build(cardEl);
    log.appendChild(cardEl);
    scrollEnd();
  }
  function pill(text, primary, onclick) {
    var b = el('button', 'lbs-pill' + (primary ? ' pri' : ''), text);
    b.type = 'button';
    b.onclick = onclick;
    return b;
  }
  function acts() { var a = el('div', 'acts'); for (var i = 0; i < arguments.length; i++) a.appendChild(arguments[i]); return a; }

  function offer() {
    card(function (c) {
      c.appendChild(acts(pill('Yes, ask the team', true, addressCard), pill('No thanks', false, clearCard)));
    });
  }
  function askForPerson() {
    var last = turns[turns.length - 1];
    if (!last || last.content !== OFFER) { supportRow(rich(OFFER)); turns.push({ role: 'assistant', content: OFFER }); }
    offer();
  }
  function addressCard(error) {
    card(function (c) {
      c.appendChild(el('p', '', 'Which email should we reply to?'));
      var field = el('input', 'lbs-in');
      field.type = 'email';
      field.placeholder = 'you@example.com';
      field.autocomplete = 'email';
      c.appendChild(field);
      c.appendChild(el('p', typeof error === 'string' ? 'err' : 'note', typeof error === 'string' ? error : "We'll send a code to check it's yours."));
      var go = pill('Send code', true, function () {
        var email = field.value.trim().toLowerCase();
        if (email.indexOf('@') < 1) return;
        go.disabled = true;
        post({ action: 'code', email: email }).then(function (r) { return r.json().then(function (j) { return [r.ok, j]; }); })
          .then(function (x) { if (x[0]) codeCard(email); else addressCard(x[1].error || "The code couldn't be sent."); })
          .catch(function () { addressCard("The code couldn't be sent. Try again in a minute."); });
      });
      field.onkeydown = function (e) { if (e.key === 'Enter') go.click(); };
      c.appendChild(acts(go));
      setTimeout(function () { field.focus(); }, 50);
    });
  }
  function codeCard(email, error) {
    card(function (c) {
      c.appendChild(el('p', '', 'Enter the code we sent to ' + email + '.'));
      var field = el('input', 'lbs-in');
      field.inputMode = 'numeric';
      field.autocomplete = 'one-time-code';
      field.placeholder = '6-digit code';
      c.appendChild(field);
      if (error) c.appendChild(el('p', 'err', error));
      var go = pill('Send to the team', true, function () {
        var code = field.value.replace(/\D/g, '');
        if (code.length !== 6) return;
        go.disabled = true;
        post({ action: 'send', kind: 'reply', email: email, code: code, messages: turns, app: 'Website' })
          .then(function (r) { return r.json().then(function (j) { return [r.ok, j]; }); })
          .then(function (x) {
            if (!x[0]) { codeCard(email, x[1].error || "That didn't go through."); return; }
            clearCard();
            var done = 'Done. Someone on the team will reply to you at ' + email + ". You'll get a copy of this conversation there too.";
            supportRow(rich(done));
            turns.push({ role: 'assistant', content: done });
          })
          .catch(function () { codeCard(email, "That didn't go through. Try again in a minute."); });
      });
      field.onkeydown = function (e) { if (e.key === 'Enter') go.click(); };
      c.appendChild(acts(go, pill('Change email', false, addressCard)));
      setTimeout(function () { field.focus(); }, 50);
    });
  }
  function reviewCard() {
    card(function (c) {
      c.appendChild(el('p', '', "Sorry that didn't help. Can I send this conversation to the longbook team so they can do better?"));
      var go = pill('Send it', true, function () {
        go.disabled = true;
        post({ action: 'send', kind: 'review', rating: 'down', messages: turns, app: 'Website' }).finally(function () {
          clearCard();
          supportRow('Thanks, the team will read it.');
        });
      });
      c.appendChild(acts(go, pill('No thanks', false, clearCard)));
      c.appendChild(el('p', 'note', 'No email address goes with it.'));
    });
  }

  function sync() {
    input.style.height = 'auto';
    input.style.height = Math.min(120, input.scrollHeight) + 'px';
    send.classList.toggle('on', !busy && input.value.trim() !== '');
  }

  function build() {
    var style = el('style');
    style.textContent = css;
    document.head.appendChild(style);
    root = el('div', 'lbs');
    root.setAttribute('role', 'dialog');
    root.setAttribute('aria-label', 'longbook Support');
    var bar = el('div', 'lbs-bar');
    bar.appendChild(supportAvatar());
    var t = el('div');
    t.appendChild(el('b', '', 'longbook Support'));
    t.appendChild(el('small', '', 'AI · answers right away'));
    bar.appendChild(t);
    bar.appendChild(el('span', 'sp'));
    var person = el('button', 'lbs-ib');
    person.type = 'button';
    person.title = 'Ask a person';
    person.setAttribute('aria-label', 'Ask a person');
    person.innerHTML = ICON.person;
    person.onclick = askForPerson;
    var close = el('button', 'lbs-ib');
    close.type = 'button';
    close.setAttribute('aria-label', 'Close Support');
    close.innerHTML = ICON.close;
    close.onclick = hide;
    bar.appendChild(person);
    bar.appendChild(close);
    log = el('div', 'lbs-log');
    log.setAttribute('aria-live', 'polite');
    var foot = el('div', 'lbs-foot');
    input = el('textarea');
    input.rows = 1;
    input.placeholder = 'Ask a question';
    input.setAttribute('aria-label', 'Ask a question');
    input.oninput = sync;
    input.onkeydown = function (e) { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); ask(input.value); } };
    send = el('button', 'lbs-send');
    send.type = 'button';
    send.setAttribute('aria-label', 'Send');
    send.innerHTML = ICON.up;
    send.onclick = function () { ask(input.value); };
    foot.appendChild(input);
    foot.appendChild(send);
    root.appendChild(bar);
    root.appendChild(log);
    root.appendChild(foot);
    document.body.appendChild(root);
    supportRow(rich(GREETING));
    var starters = el('div', 'lbs-starters');
    STARTERS.forEach(function (s) { starters.appendChild(pill(s, false, function () { ask(s); })); });
    log.appendChild(starters);
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && root.classList.contains('on')) hide(); });
  }

  function show() {
    if (!root) build();
    root.style.display = 'flex';
    requestAnimationFrame(function () { root.classList.add('on'); input.focus(); });
  }
  function hide() {
    root.classList.remove('on');
    setTimeout(function () { if (!root.classList.contains('on')) root.style.display = 'none'; }, 280);
  }

  window.lbSupport = { open: show };
})();
