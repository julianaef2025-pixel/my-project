'use strict';

// ── Typing badge ──────────────────────────────────────────────────────────────
const badge = document.getElementById('typingBadge');
const phrases = [
  'Machine Learning',
  'LLM Fine-tuning',
  'MLOps at Scale',
  'Vector Search',
  'Responsible AI',
];
let phraseIdx = 0, charIdx = 0, deleting = false;

function typeTick() {
  const phrase = phrases[phraseIdx];
  if (!deleting) {
    badge.textContent = phrase.slice(0, ++charIdx);
    if (charIdx === phrase.length) {
      deleting = true;
      setTimeout(typeTick, 1800);
      return;
    }
  } else {
    badge.textContent = phrase.slice(0, --charIdx);
    if (charIdx === 0) {
      deleting = false;
      phraseIdx = (phraseIdx + 1) % phrases.length;
    }
  }
  setTimeout(typeTick, deleting ? 45 : 80);
}
typeTick();

// ── Animated counters ─────────────────────────────────────────────────────────
function animateCounter(el) {
  const target = +el.dataset.target;
  const duration = 1600;
  const start = performance.now();
  function step(now) {
    const p = Math.min((now - start) / duration, 1);
    const ease = 1 - Math.pow(1 - p, 3);
    el.textContent = Math.round(ease * target).toLocaleString();
    if (p < 1) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
}

const statEls = document.querySelectorAll('.stat-num');
const statsObs = new IntersectionObserver(entries => {
  entries.forEach(e => {
    if (e.isIntersecting) {
      animateCounter(e.target);
      statsObs.unobserve(e.target);
    }
  });
}, { threshold: .5 });
statEls.forEach(el => statsObs.observe(el));

// ── Scroll reveal for about cards ────────────────────────────────────────────
const revealCards = document.querySelectorAll('.about-card');
const cardObs = new IntersectionObserver(entries => {
  entries.forEach(e => {
    if (e.isIntersecting) {
      const delay = +(e.target.dataset.delay || 0);
      setTimeout(() => e.target.classList.add('visible'), delay);
      cardObs.unobserve(e.target);
    }
  });
}, { threshold: .2 });
revealCards.forEach(c => cardObs.observe(c));

// ── Tools filter ──────────────────────────────────────────────────────────────
const filterBtns = document.querySelectorAll('.filter-btn');
const toolCards  = document.querySelectorAll('.tool-card');

filterBtns.forEach(btn => {
  btn.addEventListener('click', () => {
    filterBtns.forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    const filter = btn.dataset.filter;
    toolCards.forEach(card => {
      const match = filter === 'all' || card.dataset.category === filter;
      card.classList.toggle('hidden', !match);
    });
  });
});

// ── Mobile nav toggle ────────────────────────────────────────────────────────
document.getElementById('navToggle').addEventListener('click', () => {
  document.querySelector('.nav-links').classList.toggle('open');
});

// ── Newsletter form ───────────────────────────────────────────────────────────
document.getElementById('newsletterForm').addEventListener('submit', e => {
  e.preventDefault();
  const input = document.getElementById('emailInput');
  const msg   = document.getElementById('formMsg');
  if (!input.value) return;
  msg.textContent = `You're on the list — welcome, ${input.value.split('@')[0]}!`;
  input.value = '';
  setTimeout(() => { msg.textContent = ''; }, 5000);
});

// ── Neural network canvas ────────────────────────────────────────────────────
(function () {
  const canvas = document.getElementById('neuralCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');

  const NODES = 38;
  const CONNECTIONS = 55;
  let W, H, nodes = [], edges = [];

  function resize() {
    W = canvas.width  = canvas.offsetWidth;
    H = canvas.height = canvas.offsetHeight;
    init();
  }

  function randRange(a, b) { return a + Math.random() * (b - a); }

  function init() {
    nodes = Array.from({ length: NODES }, () => ({
      x:  randRange(.05, .95) * W,
      y:  randRange(.05, .95) * H,
      vx: randRange(-.3, .3),
      vy: randRange(-.3, .3),
      r:  randRange(2.5, 5),
      pulse: Math.random() * Math.PI * 2,
    }));

    edges = [];
    for (let i = 0; i < CONNECTIONS; i++) {
      const a = Math.floor(Math.random() * NODES);
      let   b = Math.floor(Math.random() * NODES);
      while (b === a) b = Math.floor(Math.random() * NODES);
      edges.push({ a, b, progress: Math.random(), speed: randRange(.003, .009), active: Math.random() > .4 });
    }
  }

  function draw() {
    ctx.clearRect(0, 0, W, H);

    // Edges
    edges.forEach(edge => {
      const na = nodes[edge.a], nb = nodes[edge.b];
      const dx = nb.x - na.x, dy = nb.y - na.y;
      const dist = Math.hypot(dx, dy);
      if (dist > 350) return;

      const alpha = Math.max(0, 1 - dist / 350) * .18;
      ctx.strokeStyle = `rgba(99,102,241,${alpha})`;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(na.x, na.y);
      ctx.lineTo(nb.x, nb.y);
      ctx.stroke();

      if (edge.active) {
        edge.progress += edge.speed;
        if (edge.progress > 1) { edge.progress = 0; edge.active = Math.random() > .3; }
        const px = na.x + dx * edge.progress;
        const py = na.y + dy * edge.progress;
        const ga = ctx.createRadialGradient(px, py, 0, px, py, 6);
        ga.addColorStop(0, 'rgba(99,102,241,.9)');
        ga.addColorStop(1, 'rgba(99,102,241,0)');
        ctx.fillStyle = ga;
        ctx.beginPath();
        ctx.arc(px, py, 6, 0, Math.PI * 2);
        ctx.fill();
      }
    });

    // Nodes
    nodes.forEach(n => {
      n.pulse += .025;
      const glow = Math.sin(n.pulse) * .4 + .5;
      const g = ctx.createRadialGradient(n.x, n.y, 0, n.x, n.y, n.r * 3);
      g.addColorStop(0, `rgba(99,102,241,${.7 * glow})`);
      g.addColorStop(.5, `rgba(34,211,238,${.3 * glow})`);
      g.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(n.x, n.y, n.r * 3, 0, Math.PI * 2);
      ctx.fill();

      ctx.fillStyle = `rgba(220,230,255,${.6 + .4 * glow})`;
      ctx.beginPath();
      ctx.arc(n.x, n.y, n.r, 0, Math.PI * 2);
      ctx.fill();

      n.x += n.vx; n.y += n.vy;
      if (n.x < 0 || n.x > W) n.vx *= -1;
      if (n.y < 0 || n.y > H) n.vy *= -1;
    });

    requestAnimationFrame(draw);
  }

  window.addEventListener('resize', resize);
  resize();
  draw();
})();
