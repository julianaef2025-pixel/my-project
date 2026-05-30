'use strict';

// ── State ──────────────────────────────────────────────────────────────────────
const sessions = [];   // [{id, title, messages:[{role,content}]}]
let activeId   = null;

// ── DOM ────────────────────────────────────────────────────────────────────────
const welcome     = document.getElementById('welcome');
const messagesEl  = document.getElementById('messages');
const userInput   = document.getElementById('userInput');
const sendBtn     = document.getElementById('sendBtn');
const newChatBtn  = document.getElementById('newChatBtn');
const historyList = document.getElementById('historyList');

// ── Auto-grow textarea ─────────────────────────────────────────────────────────
userInput.addEventListener('input', () => {
  userInput.style.height = 'auto';
  userInput.style.height = Math.min(userInput.scrollHeight, 220) + 'px';
  sendBtn.disabled = !userInput.value.trim();
});

userInput.addEventListener('keydown', e => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    if (!sendBtn.disabled) submit();
  }
});

sendBtn.addEventListener('click', submit);

// ── Suggestion pills ───────────────────────────────────────────────────────────
document.querySelectorAll('.suggestion-pill').forEach(btn => {
  btn.addEventListener('click', () => {
    userInput.value = btn.dataset.text;
    userInput.dispatchEvent(new Event('input'));
    submit();
  });
});

// ── New chat ───────────────────────────────────────────────────────────────────
newChatBtn.addEventListener('click', () => startSession());

// ── Session management ─────────────────────────────────────────────────────────
function startSession() {
  const id = Date.now().toString();
  sessions.push({ id, title: 'New chat', messages: [] });
  activeId = id;
  renderHistory();
  clearThread();
}

function activeSession() {
  return sessions.find(s => s.id === activeId);
}

function clearThread() {
  messagesEl.innerHTML = '';
  messagesEl.classList.remove('visible');
  welcome.style.display = 'flex';
  userInput.value = '';
  userInput.style.height = 'auto';
  sendBtn.disabled = true;
  userInput.focus();
}

function renderHistory() {
  historyList.innerHTML = '';
  [...sessions].reverse().forEach(s => {
    const el = document.createElement('div');
    el.className = 'history-item' + (s.id === activeId ? ' active' : '');
    el.textContent = s.title;
    el.addEventListener('click', () => switchSession(s.id));
    historyList.appendChild(el);
  });
}

function switchSession(id) {
  activeId = id;
  renderHistory();
  const s = activeSession();
  messagesEl.innerHTML = '';
  if (s.messages.length === 0) {
    clearThread();
    return;
  }
  welcome.style.display = 'none';
  messagesEl.classList.add('visible');
  s.messages.forEach(m => appendMessage(m.role, m.content, false));
  scrollBottom();
}

// ── Main submit ────────────────────────────────────────────────────────────────
async function submit() {
  const text = userInput.value.trim();
  if (!text) return;

  if (!activeId) startSession();

  const session = activeSession();

  // Show thread, hide welcome
  welcome.style.display = 'none';
  messagesEl.classList.add('visible');

  // Add user message
  session.messages.push({ role: 'user', content: text });
  appendMessage('user', text);

  // Update sidebar title
  if (session.title === 'New chat') {
    session.title = text.slice(0, 40) + (text.length > 40 ? '…' : '');
    renderHistory();
  }

  // Reset input
  userInput.value = '';
  userInput.style.height = 'auto';
  sendBtn.disabled = true;

  // Typing indicator
  const typingRow = appendTyping();
  scrollBottom();

  try {
    const reply = await fetchReply(session.messages);
    typingRow.remove();
    session.messages.push({ role: 'assistant', content: reply });
    appendMessage('assistant', reply);
    scrollBottom();
  } catch (err) {
    typingRow.remove();
    appendMessage('assistant', `**Error:** ${err.message}`);
    scrollBottom();
  }
}

// ── API call ───────────────────────────────────────────────────────────────────
async function fetchReply(messages) {
  const res = await fetch('/api/chat', {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify({ messages }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || `HTTP ${res.status}`);
  }

  const data = await res.json();
  return data.reply;
}

// ── Render helpers ─────────────────────────────────────────────────────────────
function appendMessage(role, content, addToDOM = true) {
  const row = document.createElement('div');
  row.className = `msg-row ${role}`;

  const avatar = document.createElement('div');
  avatar.className = 'msg-avatar';
  avatar.textContent = role === 'assistant' ? 'D' : 'U';

  const bubble = document.createElement('div');
  bubble.className = 'msg-bubble';

  if (role === 'assistant') {
    bubble.innerHTML = renderMarkdown(content);
    // Add copy buttons to code blocks
    bubble.querySelectorAll('pre').forEach(pre => {
      const wrap = document.createElement('div');
      wrap.className = 'code-wrap';
      pre.replaceWith(wrap);
      wrap.appendChild(pre);

      const btn = document.createElement('button');
      btn.className = 'copy-btn';
      btn.textContent = 'Copy';
      btn.addEventListener('click', () => {
        navigator.clipboard.writeText(pre.querySelector('code')?.innerText ?? pre.innerText);
        btn.textContent = 'Copied!';
        setTimeout(() => { btn.textContent = 'Copy'; }, 1500);
      });
      wrap.appendChild(btn);
    });
  } else {
    bubble.textContent = content;
  }

  if (role === 'assistant') {
    row.appendChild(avatar);
    row.appendChild(bubble);
  } else {
    row.appendChild(bubble);
    row.appendChild(avatar);
  }

  if (addToDOM) messagesEl.appendChild(row);
  return row;
}

function appendTyping() {
  const row = document.createElement('div');
  row.className = 'msg-row assistant';

  const avatar = document.createElement('div');
  avatar.className = 'msg-avatar';
  avatar.textContent = 'D';

  const bubble = document.createElement('div');
  bubble.className = 'msg-bubble';
  bubble.innerHTML = '<div class="typing-dots"><span></span><span></span><span></span></div>';

  row.appendChild(avatar);
  row.appendChild(bubble);
  messagesEl.appendChild(row);
  return row;
}

function scrollBottom() {
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

// ── Minimal markdown renderer ──────────────────────────────────────────────────
function renderMarkdown(text) {
  let html = escapeHtml(text);

  // Fenced code blocks (``` lang\n...\n```)
  html = html.replace(/```(\w*)\n?([\s\S]*?)```/g, (_, lang, code) => {
    return `<pre><code class="language-${lang}">${code.trimEnd()}</code></pre>`;
  });

  // Inline code
  html = html.replace(/`([^`\n]+)`/g, '<code>$1</code>');

  // Bold **text**
  html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');

  // Italic *text* or _text_
  html = html.replace(/\*([^*\n]+)\*/g, '<em>$1</em>');
  html = html.replace(/_([^_\n]+)_/g, '<em>$1</em>');

  // Headings
  html = html.replace(/^### (.+)$/gm, '<h3>$1</h3>');
  html = html.replace(/^## (.+)$/gm, '<h2>$1</h2>');
  html = html.replace(/^# (.+)$/gm, '<h1>$1</h1>');

  // Blockquote
  html = html.replace(/^&gt; (.+)$/gm, '<blockquote>$1</blockquote>');

  // Horizontal rule
  html = html.replace(/^---$/gm, '<hr>');

  // Unordered list items
  html = html.replace(/^\s*[-*] (.+)$/gm, '<li>$1</li>');
  html = html.replace(/(<li>[\s\S]*?<\/li>)(?=\n<li>|$)/g, '<ul>$1</ul>');

  // Ordered list items
  html = html.replace(/^\d+\. (.+)$/gm, '<li>$1</li>');

  // Links [text](url)
  html = html.replace(/\[([^\]]+)\]\((https?:\/\/[^\)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');

  // Paragraphs: split on double newlines
  const blocks = html.split(/\n\n+/);
  html = blocks.map(block => {
    block = block.trim();
    if (!block) return '';
    if (/^<(h[1-3]|ul|ol|li|pre|blockquote|hr)/.test(block)) return block;
    return `<p>${block.replace(/\n/g, '<br>')}</p>`;
  }).join('\n');

  return html;
}

function escapeHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ── Init ───────────────────────────────────────────────────────────────────────
startSession();
userInput.focus();
