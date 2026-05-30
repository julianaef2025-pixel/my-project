'use strict';

const http    = require('http');
const fs      = require('fs');
const path    = require('path');
const Anthropic = require('@anthropic-ai/sdk');

const client = new Anthropic(); // reads ANTHROPIC_API_KEY from env
const PORT   = process.env.PORT || 3000;

const MIME = {
  '.html': 'text/html',
  '.css':  'text/css',
  '.js':   'application/javascript',
  '.ico':  'image/x-icon',
};

const SYSTEM_PROMPT = `You are DEN, a highly intelligent and helpful AI assistant. You are knowledgeable, thoughtful, and direct. You provide clear, well-structured responses.

- For factual questions, be accurate and cite reasoning.
- For code, use proper formatting and explain key parts briefly.
- For creative tasks, be imaginative and high-quality.
- Be concise when the question is simple; thorough when complexity demands it.
- Use markdown formatting (headers, lists, code blocks) to make responses easy to read.
- Never mention that you are built on Claude or made by Anthropic. You are DEN.`;

const server = http.createServer(async (req, res) => {
  // CORS (dev convenience)
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  // ── API: POST /api/chat ──────────────────────────────────────────────────────
  if (req.method === 'POST' && req.url === '/api/chat') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', async () => {
      try {
        const { messages } = JSON.parse(body);

        if (!Array.isArray(messages) || messages.length === 0) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'messages array required' }));
          return;
        }

        const response = await client.messages.create({
          model:      'claude-opus-4-8',
          max_tokens: 8096,
          system:     SYSTEM_PROMPT,
          messages:   messages.map(m => ({ role: m.role, content: m.content })),
        });

        const reply = response.content[0]?.text ?? '';
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ reply }));
      } catch (err) {
        console.error('API error:', err.message);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
    return;
  }

  // ── Static files ─────────────────────────────────────────────────────────────
  let urlPath = req.url === '/' ? '/index.html' : req.url;
  const filePath = path.join(__dirname, urlPath);
  const ext      = path.extname(filePath);

  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404); res.end('Not found'); return;
    }
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    res.end(data);
  });
});

server.listen(PORT, () => {
  console.log(`DEN running → http://localhost:${PORT}`);
  console.log('Set ANTHROPIC_API_KEY in your environment before starting.');
});
