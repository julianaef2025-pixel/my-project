'use strict';

// ── API key setup ──────────────────────────────────────────────────────────────
const modalOverlay = document.getElementById('modalOverlay');
const apiKeyInput  = document.getElementById('apiKeyInput');
const modalSaveBtn = document.getElementById('modalSaveBtn');
const modalError   = document.getElementById('modalError');
const changeKeyBtn = document.getElementById('changeKeyBtn');

let API_KEY = localStorage.getItem('den_api_key') || '';

function showModal() {
  modalOverlay.classList.remove('hidden');
  apiKeyInput.value = '';
  apiKeyInput.focus();
}
function hideModal() {
  modalOverlay.classList.add('hidden');
}

if (!API_KEY) {
  showModal();
} else {
  hideModal();
}

modalSaveBtn.addEventListener('click', saveKey);
apiKeyInput.addEventListener('keydown', e => { if (e.key === 'Enter') saveKey(); });
changeKeyBtn.addEventListener('click', showModal);

function saveKey() {
  const key = apiKeyInput.value.trim();
  if (!key.startsWith('sk-ant-')) {
    modalError.textContent = 'Key should start with sk-ant-';
    return;
  }
  API_KEY = key;
  localStorage.setItem('den_api_key', key);
  modalError.textContent = '';
  hideModal();
  userInput.focus();
}

// ── State ──────────────────────────────────────────────────────────────────────
let sessions  = [];   // [{id, title, messages:[{role,content}]}]
let activeId  = null;
let isBusy    = false;

// ── DOM ────────────────────────────────────────────────────────────────────────
const welcome     = document.getElementById('welcome');
const messagesEl  = document.getElementById('messages');
const userInput   = document.getElementById('userInput');
const sendBtn     = document.getElementById('sendBtn');
const newChatBtn  = document.getElementById('newChatBtn');
const historyList = document.getElementById('historyList');

// ── Textarea auto-grow ─────────────────────────────────────────────────────────
userInput.addEventListener('input', () => {
  userInput.style.height = 'auto';
  userInput.style.height = Math.min(userInput.scrollHeight, 200) + 'px';
});

userInput.addEventListener('keydown', e => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    if (!isBusy) submit();
  }
});

sendBtn.addEventListener('click', () => { if (!isBusy) submit(); });
newChatBtn.addEventListener('click', newChat);

// ── Suggestion pills ───────────────────────────────────────────────────────────
document.querySelectorAll('.pill').forEach(btn => {
  btn.addEventListener('click', () => {
    userInput.value = btn.dataset.q;
    userInput.dispatchEvent(new Event('input'));
    submit();
  });
});

// ── Session helpers ────────────────────────────────────────────────────────────
function newChat() {
  const id = String(Date.now());
  sessions.unshift({ id, title: 'New chat', messages: [] });
  activeId = id;
  renderHistory();
  showWelcome();
  userInput.value = '';
  userInput.style.height = 'auto';
  userInput.focus();
}

function getActive() {
  return sessions.find(s => s.id === activeId);
}

function showWelcome() {
  welcome.style.display  = 'flex';
  messagesEl.className   = 'messages';
  messagesEl.innerHTML   = '';
}

function showThread() {
  welcome.style.display = 'none';
  messagesEl.classList.add('show');
}

function renderHistory() {
  historyList.innerHTML = '';
  sessions.forEach(s => {
    const el = document.createElement('div');
    el.className   = 'history-item' + (s.id === activeId ? ' active' : '');
    el.textContent = s.title;
    el.addEventListener('click', () => loadSession(s.id));
    historyList.appendChild(el);
  });
}

function loadSession(id) {
  activeId = id;
  renderHistory();
  const s = getActive();
  messagesEl.innerHTML = '';
  if (!s.messages.length) { showWelcome(); return; }
  showThread();
  s.messages.forEach(m => addBubble(m.role, m.content));
  scrollBottom();
}

// ── Submit ─────────────────────────────────────────────────────────────────────
async function submit() {
  const text = userInput.value.trim();
  if (!text || isBusy) return;

  if (!API_KEY) { showModal(); return; }
  if (!activeId) newChat();

  const session = getActive();
  showThread();

  session.messages.push({ role: 'user', content: text });
  addBubble('user', text);

  if (session.title === 'New chat') {
    session.title = text.slice(0, 42) + (text.length > 42 ? '…' : '');
    renderHistory();
  }

  userInput.value = '';
  userInput.style.height = 'auto';
  scrollBottom();

  isBusy = true;
  sendBtn.classList.add('loading');

  const typingEl = addTyping();
  scrollBottom();

  try {
    const reply = await callAPI(session.messages);
    typingEl.remove();
    session.messages.push({ role: 'assistant', content: reply });
    addBubble('assistant', reply);
    scrollBottom();
  } catch (err) {
    typingEl.remove();
    addBubble('assistant', `**Error:** ${err.message}\n\nIf this is an auth error, click **Change API key** in the sidebar.`);
    scrollBottom();
  } finally {
    isBusy = false;
    sendBtn.classList.remove('loading');
    userInput.focus();
  }
}

// ── Anthropic API call (direct from browser) ───────────────────────────────────
async function callAPI(messages) {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type':                        'application/json',
      'x-api-key':                           API_KEY,
      'anthropic-version':                   '2023-06-01',
      'anthropic-dangerous-direct-browser-access': 'true',
    },
    body: JSON.stringify({
      model:      'claude-opus-4-8',
      max_tokens: 8096,
      system: `You are DEN, a highly intelligent and helpful AI assistant. Be clear, thorough, and well-structured. Use markdown formatting — headers, bullet points, and code blocks — to make responses easy to read. Never mention Claude or Anthropic.`,
      messages: messages.map(m => ({ role: m.role, content: m.content })),
    }),
  });

  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    const msg  = body?.error?.message || `HTTP ${res.status}`;
    throw new Error(msg);
  }

  const data = await res.json();
  return data.content?.[0]?.text ?? '(empty response)';
}

// ── Render helpers ─────────────────────────────────────────────────────────────
function addBubble(role, content) {
  const row    = document.createElement('div');
  row.className = `msg-row ${role}`;

  const av = document.createElement('div');
  av.className   = 'avatar';
  av.textContent = role === 'assistant' ? 'D' : 'U';

  const bub = document.createElement('div');
  bub.className = 'bubble';

  if (role === 'assistant') {
    bub.innerHTML = md(content);
    // Add copy buttons to code blocks
    bub.querySelectorAll('pre').forEach(pre => {
      const wrap = document.createElement('div');
      wrap.className = 'code-wrap';
      pre.replaceWith(wrap);
      wrap.appendChild(pre);
      const cp = document.createElement('button');
      cp.className   = 'copy-btn';
      cp.textContent = 'Copy';
      cp.onclick = () => {
        const txt = pre.querySelector('code')?.innerText ?? pre.innerText;
        navigator.clipboard.writeText(txt).then(() => {
          cp.textContent = 'Copied!';
          setTimeout(() => { cp.textContent = 'Copy'; }, 1600);
        });
      };
      wrap.appendChild(cp);
    });
  } else {
    bub.textContent = content;
  }

  if (role === 'assistant') { row.appendChild(av); row.appendChild(bub); }
  else                       { row.appendChild(bub); row.appendChild(av); }

  messagesEl.appendChild(row);
  return row;
}

function addTyping() {
  const row    = document.createElement('div');
  row.className = 'msg-row assistant';
  const av = document.createElement('div');
  av.className   = 'avatar';
  av.textContent = 'D';
  const bub = document.createElement('div');
  bub.className = 'bubble';
  bub.innerHTML = '<div class="dots"><span></span><span></span><span></span></div>';
  row.appendChild(av);
  row.appendChild(bub);
  messagesEl.appendChild(row);
  return row;
}

function scrollBottom() {
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

// ── Minimal markdown renderer ──────────────────────────────────────────────────
function md(raw) {
  let s = esc(raw);

  // Fenced code blocks
  s = s.replace(/```(\w*)\n([\s\S]*?)```/g, (_, lang, code) =>
    `<pre><code>${code.trimEnd()}</code></pre>`);

  // Inline code
  s = s.replace(/`([^`\n]+)`/g, '<code>$1</code>');

  // Bold & italic
  s = s.replace(/\*\*\*(.+?)\*\*\*/g, '<strong><em>$1</em></strong>');
  s = s.replace(/\*\*(.+?)\*\*/g,     '<strong>$1</strong>');
  s = s.replace(/\*([^*\n]+)\*/g,     '<em>$1</em>');
  s = s.replace(/_([^_\n]+)_/g,       '<em>$1</em>');

  // Headings
  s = s.replace(/^### (.+)$/gm, '<h3>$1</h3>');
  s = s.replace(/^## (.+)$/gm,  '<h2>$1</h2>');
  s = s.replace(/^# (.+)$/gm,   '<h1>$1</h1>');

  // Blockquote
  s = s.replace(/^&gt; (.+)$/gm, '<blockquote>$1</blockquote>');

  // HR
  s = s.replace(/^---$/gm, '<hr>');

  // Lists
  s = s.replace(/^[ \t]*[-*] (.+)$/gm, '<li>$1</li>');
  s = s.replace(/^[ \t]*\d+\. (.+)$/gm, '<li>$1</li>');
  s = s.replace(/(<li>.*<\/li>)/s, '<ul>$1</ul>');

  // Links
  s = s.replace(/\[([^\]]+)\]\((https?:\/\/[^)]+)\)/g,
    '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');

  // Paragraphs
  s = s.split(/\n{2,}/).map(block => {
    block = block.trim();
    if (!block) return '';
    if (/^<(h[1-3]|ul|ol|li|pre|blockquote|hr)/.test(block)) return block;
    return `<p>${block.replace(/\n/g, '<br>')}</p>`;
  }).join('\n');

  return s;
}

function esc(s) {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ── Boot ───────────────────────────────────────────────────────────────────────
newChat();
