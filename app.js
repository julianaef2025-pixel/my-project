'use strict';

// ── Password Checker (HIBP k-anonymity, free, no key needed) ──────────────────

async function sha1(str) {
  const buf = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(str));
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('').toUpperCase();
}

async function checkPassword(password) {
  const hash   = await sha1(password);
  const prefix = hash.slice(0, 5);
  const suffix = hash.slice(5);

  const res = await fetch(`https://api.pwnedpasswords.com/range/${prefix}`, {
    headers: { 'Add-Padding': 'true' }
  });
  if (!res.ok) throw new Error('HIBP API error: ' + res.status);

  const text  = await res.text();
  const match = text.split('\n').find(line => line.startsWith(suffix));
  if (!match) return 0;
  return parseInt(match.split(':')[1].trim(), 10);
}

const pwInput  = document.getElementById('pwInput');
const pwBtn    = document.getElementById('pwBtn');
const pwResult = document.getElementById('pwResult');
const pwToggle = document.getElementById('pwToggle');

pwToggle.addEventListener('click', () => {
  const show = pwInput.type === 'password';
  pwInput.type = show ? 'text' : 'password';
  pwToggle.textContent = show ? '🚫' : '👁';
});

pwBtn.addEventListener('click', async () => {
  const pw = pwInput.value.trim();
  if (!pw) return showResult(pwResult, 'Enter a password first.', 'warn');

  pwBtn.disabled = true;
  pwBtn.textContent = 'Checking…';
  try {
    const count = await checkPassword(pw);
    if (count === 0) {
      showResult(pwResult,
        '<span class="safe-icon">&#x2705;</span> <strong>Not found</strong> in any known breach. Looks safe — but use a password manager and stay unique across sites.',
        'safe');
    } else {
      showResult(pwResult,
        `<span class="danger-icon">&#x26A0;&#xFE0F;</span> <strong>Exposed ${count.toLocaleString()} times</strong> in known data breaches. Stop using this password immediately and change it everywhere you use it.`,
        'danger');
    }
  } catch (e) {
    showResult(pwResult, 'Error: ' + e.message, 'warn');
  } finally {
    pwBtn.disabled = false;
    pwBtn.textContent = 'Check Password';
  }
});

pwInput.addEventListener('keydown', e => { if (e.key === 'Enter') pwBtn.click(); });

// ── Email Checker (requires free HIBP API key) ────────────────────────────────

const emailInput  = document.getElementById('emailInput');
const apiKeyInput = document.getElementById('apiKeyInput');
const emailBtn    = document.getElementById('emailBtn');
const emailResult = document.getElementById('emailResult');

emailBtn.addEventListener('click', async () => {
  const email  = emailInput.value.trim();
  const apiKey = apiKeyInput.value.trim();

  if (!apiKey) {
    return showResult(emailResult,
      '&#x1F511; Paste your free HIBP API key first. <a href="https://haveibeenpwned.com/API/Key" target="_blank" rel="noopener">Get one free here</a> — it takes 30 seconds.',
      'warn');
  }
  if (!email || !email.includes('@')) {
    return showResult(emailResult, 'Enter a valid email address.', 'warn');
  }

  emailBtn.disabled = true;
  emailBtn.textContent = 'Checking…';

  try {
    const res = await fetch(
      `https://haveibeenpwned.com/api/v3/breachedaccount/${encodeURIComponent(email)}?truncateResponse=false`,
      { headers: { 'hibp-api-key': apiKey, 'user-agent': 'DarkWebMonitor' } }
    );

    if (res.status === 404) {
      showResult(emailResult,
        '<span class="safe-icon">&#x2705;</span> <strong>Good news!</strong> This email wasn\'t found in any known breaches.',
        'safe');
    } else if (res.status === 401) {
      showResult(emailResult, '&#x1F6AB; Invalid API key. Double-check and try again.', 'warn');
    } else if (res.status === 429) {
      showResult(emailResult, '&#x23F3; Rate limited — wait a moment and try again.', 'warn');
    } else if (!res.ok) {
      showResult(emailResult, 'API error: ' + res.status, 'warn');
    } else {
      const breaches = await res.json();
      renderEmailBreaches(breaches);
    }
  } catch (e) {
    showResult(emailResult,
      '&#x26A0;&#xFE0F; Network error — this may be a CORS issue if running from a local file. Try hosting the page on a server (e.g. VS Code Live Server).',
      'warn');
  } finally {
    emailBtn.disabled = false;
    emailBtn.textContent = 'Check Email';
  }
});

emailInput.addEventListener('keydown', e => { if (e.key === 'Enter') emailBtn.click(); });

function renderEmailBreaches(breaches) {
  const count = breaches.length;
  let html = `<div class="breach-summary danger">
    <span class="danger-icon">&#x26A0;&#xFE0F;</span>
    <strong>Found in ${count} breach${count === 1 ? '' : 'es'}</strong>
  </div><div class="breach-list">`;

  for (const b of breaches) {
    const types = (b.DataClasses || []).slice(0, 5).join(', ');
    html += `
      <div class="breach-item">
        <div class="breach-item-header">
          <strong>${escHtml(b.Title)}</strong>
          <span class="breach-date">${b.BreachDate ? b.BreachDate.slice(0, 7) : 'Unknown'}</span>
        </div>
        <div class="breach-meta">
          ${b.PwnCount ? `<span class="badge badge-red">${(b.PwnCount / 1e6).toFixed(1)}M accounts</span>` : ''}
          ${b.IsVerified ? '' : '<span class="badge badge-gray">Unverified</span>'}
          ${b.IsSensitive ? '<span class="badge badge-orange">Sensitive</span>' : ''}
        </div>
        ${types ? `<div class="breach-types">Data: ${escHtml(types)}${b.DataClasses.length > 5 ? ` +${b.DataClasses.length - 5} more` : ''}</div>` : ''}
      </div>`;
  }
  html += '</div>';
  showResult(emailResult, html, 'danger');
}

// ── Breach Feed (free, no key) ────────────────────────────────────────────────

const feedList   = document.getElementById('feedList');
const feedSearch = document.getElementById('feedSearch');
const feedSort   = document.getElementById('feedSort');
const feedCount  = document.getElementById('feedCount');

let allBreaches = [];

async function loadFeed() {
  try {
    const res = await fetch('https://haveibeenpwned.com/api/v3/breaches');
    if (!res.ok) throw new Error('Status ' + res.status);
    allBreaches = await res.json();
    feedCount.textContent = allBreaches.length + ' breaches';
    renderFeed();
  } catch (e) {
    feedList.innerHTML = `<div class="feed-error">&#x26A0;&#xFE0F; Could not load breach data: ${e.message}</div>`;
  }
}

function renderFeed() {
  const query = feedSearch.value.toLowerCase();
  const sort  = feedSort.value;

  let items = allBreaches.filter(b =>
    b.Name.toLowerCase().includes(query) ||
    b.Title.toLowerCase().includes(query) ||
    (b.Domain || '').toLowerCase().includes(query)
  );

  if (sort === 'date-desc') items.sort((a, b) => b.BreachDate.localeCompare(a.BreachDate));
  else if (sort === 'date-asc') items.sort((a, b) => a.BreachDate.localeCompare(b.BreachDate));
  else if (sort === 'size-desc') items.sort((a, b) => (b.PwnCount || 0) - (a.PwnCount || 0));

  if (items.length === 0) {
    feedList.innerHTML = '<div class="feed-empty">No breaches match your search.</div>';
    return;
  }

  feedList.innerHTML = items.slice(0, 80).map(b => {
    const mil = b.PwnCount ? (b.PwnCount / 1e6).toFixed(1) + 'M' : '?';
    const sev = b.PwnCount > 50e6 ? 'sev-high' : b.PwnCount > 5e6 ? 'sev-med' : 'sev-low';
    return `
      <div class="feed-item ${sev}">
        <div class="feed-item-left">
          ${b.LogoPath ? `<img src="${escHtml(b.LogoPath)}" alt="" class="feed-logo" loading="lazy" onerror="this.style.display='none'" />` : '<div class="feed-logo-placeholder">?</div>'}
        </div>
        <div class="feed-item-body">
          <div class="feed-item-title">${escHtml(b.Title)}</div>
          <div class="feed-item-meta">
            <span>${b.BreachDate ? b.BreachDate.slice(0, 10) : 'Unknown date'}</span>
            <span class="dot">·</span>
            <span class="count-badge ${sev}">${mil} accounts</span>
            ${b.IsVerified ? '' : '<span class="dot">·</span><span class="unverified">Unverified</span>'}
          </div>
          ${b.DataClasses ? `<div class="feed-item-types">${b.DataClasses.slice(0, 4).map(t => `<span class="type-tag">${escHtml(t)}</span>`).join('')}${b.DataClasses.length > 4 ? `<span class="type-tag more">+${b.DataClasses.length - 4}</span>` : ''}</div>` : ''}
        </div>
      </div>`;
  }).join('');
}

feedSearch.addEventListener('input', renderFeed);
feedSort.addEventListener('change', renderFeed);

// ── Helpers ───────────────────────────────────────────────────────────────────

function showResult(el, html, type) {
  el.className = 'result-box ' + type;
  el.innerHTML = html;
}

function escHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ── Init ──────────────────────────────────────────────────────────────────────
loadFeed();
