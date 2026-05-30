'use strict';

// ═══════════════════════════════════════════════════════════
// LOADER
// ═══════════════════════════════════════════════════════════
const loader    = document.getElementById('loader');
const loaderBar = document.getElementById('loaderBar');
const loaderPct = document.getElementById('loaderPct');

let loadPct = 0;
const loadInterval = setInterval(() => {
  loadPct += Math.random() * 18 + 5;
  if (loadPct >= 100) { loadPct = 100; clearInterval(loadInterval); }
  loaderBar.style.width = loadPct + '%';
  loaderPct.textContent = Math.round(loadPct) + '%';
  if (loadPct === 100) {
    setTimeout(() => {
      loader.classList.add('hidden');
      triggerHeroReveal();
    }, 400);
  }
}, 120);

// ═══════════════════════════════════════════════════════════
// CUSTOM CURSOR
// ═══════════════════════════════════════════════════════════
const cursorRing = document.getElementById('cursorRing');
const cursorDot  = document.getElementById('cursorDot');
let mouseX = -200, mouseY = -200;
let ringX  = -200, ringY  = -200;

document.addEventListener('mousemove', e => {
  mouseX = e.clientX;
  mouseY = e.clientY;
  cursorDot.style.left = mouseX + 'px';
  cursorDot.style.top  = mouseY + 'px';
});
document.addEventListener('mouseleave', () => { cursorRing.style.opacity = '0'; cursorDot.style.opacity = '0'; });
document.addEventListener('mouseenter', () => { cursorRing.style.opacity = '1'; cursorDot.style.opacity = '1'; });
document.addEventListener('mousedown', () => cursorRing.classList.add('click'));
document.addEventListener('mouseup',   () => cursorRing.classList.remove('click'));

// Hover state on interactives
document.querySelectorAll('a, button, .tilt-card, input, .filter-btn').forEach(el => {
  el.addEventListener('mouseenter', () => cursorRing.classList.add('hover'));
  el.addEventListener('mouseleave', () => cursorRing.classList.remove('hover'));
});

// Ring lerp
function lerpCursor() {
  ringX += (mouseX - ringX) * .12;
  ringY += (mouseY - ringY) * .12;
  cursorRing.style.left = ringX + 'px';
  cursorRing.style.top  = ringY + 'px';
  requestAnimationFrame(lerpCursor);
}
lerpCursor();

// ═══════════════════════════════════════════════════════════
// SPOTLIGHT
// ═══════════════════════════════════════════════════════════
const spotlight = document.getElementById('spotlight');
document.addEventListener('mousemove', e => {
  spotlight.style.left = e.clientX + 'px';
  spotlight.style.top  = e.clientY + 'px';
});

// ═══════════════════════════════════════════════════════════
// SCROLL PROGRESS
// ═══════════════════════════════════════════════════════════
const scrollProgress = document.getElementById('scrollProgress');
window.addEventListener('scroll', () => {
  const pct = window.scrollY / (document.body.scrollHeight - window.innerHeight) * 100;
  scrollProgress.style.width = pct + '%';
}, { passive: true });

// ═══════════════════════════════════════════════════════════
// NAV SCROLL STATE + ACTIVE LINK
// ═══════════════════════════════════════════════════════════
const mainNav  = document.getElementById('mainNav');
const navLinks = document.querySelectorAll('.nav-link');
const sections = document.querySelectorAll('section[id]');

window.addEventListener('scroll', () => {
  mainNav.classList.toggle('scrolled', window.scrollY > 30);

  let current = '';
  sections.forEach(s => {
    if (window.scrollY >= s.offsetTop - 120) current = s.id;
  });
  navLinks.forEach(a => {
    a.classList.toggle('active', a.getAttribute('href') === '#' + current);
  });
}, { passive: true });

// Mobile nav
document.getElementById('navToggle').addEventListener('click', function () {
  this.classList.toggle('open');
  document.getElementById('navLinks').classList.toggle('open');
});

// ═══════════════════════════════════════════════════════════
// TYPING BADGE
// ═══════════════════════════════════════════════════════════
const badge   = document.getElementById('typingBadge');
const phrases = [
  '> Machine Learning',
  '> LLM Fine-tuning',
  '> MLOps at Scale',
  '> Vector Search',
  '> Responsible AI',
  '> RAG Systems',
];
let phraseIdx = 0, charIdx = 0, deleting = false;

function typeTick() {
  const phrase = phrases[phraseIdx];
  badge.textContent = phrase.slice(0, charIdx) + (Math.floor(Date.now() / 500) % 2 ? '█' : ' ');
  if (!deleting) {
    charIdx++;
    if (charIdx > phrase.length) { deleting = true; setTimeout(typeTick, 1600); return; }
  } else {
    charIdx--;
    if (charIdx === 0) { deleting = false; phraseIdx = (phraseIdx + 1) % phrases.length; }
  }
  setTimeout(typeTick, deleting ? 40 : 75);
}

// ═══════════════════════════════════════════════════════════
// SPLIT TITLE ANIMATION
// ═══════════════════════════════════════════════════════════
function splitTitles() {
  document.querySelectorAll('.split-title').forEach(el => {
    const words = el.innerHTML.split(/(\s+)/);
    el.innerHTML = words.map(w =>
      w.trim()
        ? `<span class="word"><span class="word-inner">${w}</span></span>`
        : w
    ).join('');
  });
}
splitTitles();

const titleObs = new IntersectionObserver(entries => {
  entries.forEach((e, i) => {
    if (e.isIntersecting) {
      const inners = e.target.querySelectorAll('.word-inner');
      inners.forEach((inner, idx) => {
        inner.style.transitionDelay = `${idx * 0.06}s`;
      });
      e.target.classList.add('visible');
      titleObs.unobserve(e.target);
    }
  });
}, { threshold: .3 });
document.querySelectorAll('.split-title').forEach(el => titleObs.observe(el));

// ═══════════════════════════════════════════════════════════
// HERO REVEAL
// ═══════════════════════════════════════════════════════════
function triggerHeroReveal() {
  typeTick();
  setTimeout(() => document.querySelector('.hero-sub')?.classList.add('visible'), 200);
  setTimeout(() => document.querySelector('.hero-cta')?.classList.add('visible'), 400);
  setTimeout(() => document.querySelector('.hero-stats')?.classList.add('visible'), 600);
  setTimeout(() => {
    document.querySelectorAll('.reveal-fade').forEach((el, i) => {
      setTimeout(() => el.classList.add('visible'), i * 120);
    });
  }, 300);
  animateCounters();
}

// ═══════════════════════════════════════════════════════════
// ANIMATED COUNTERS
// ═══════════════════════════════════════════════════════════
function animateCounters() {
  document.querySelectorAll('.stat-num').forEach(el => {
    const target = +el.dataset.target;
    const dur = 1800;
    const start = performance.now();
    function step(now) {
      const p = Math.min((now - start) / dur, 1);
      const ease = 1 - Math.pow(1 - p, 4);
      el.textContent = Math.round(ease * target).toLocaleString();
      if (p < 1) requestAnimationFrame(step);
      else spawnCounterParticles(el);
    }
    requestAnimationFrame(step);
  });
}

function spawnCounterParticles(el) {
  const rect = el.getBoundingClientRect();
  for (let i = 0; i < 8; i++) {
    const p = document.createElement('div');
    Object.assign(p.style, {
      position: 'fixed',
      left: rect.left + rect.width / 2 + 'px',
      top:  rect.top + rect.height / 2 + 'px',
      width: '4px', height: '4px',
      borderRadius: '50%',
      background: `hsl(${230 + Math.random() * 60},80%,70%)`,
      pointerEvents: 'none',
      zIndex: '9990',
      transform: 'translate(-50%,-50%)',
    });
    document.body.appendChild(p);
    const angle = (i / 8) * Math.PI * 2;
    const dist  = 30 + Math.random() * 40;
    const tx = Math.cos(angle) * dist;
    const ty = Math.sin(angle) * dist;
    p.animate([
      { transform: 'translate(-50%,-50%) translate(0,0)', opacity: 1 },
      { transform: `translate(-50%,-50%) translate(${tx}px,${ty}px)`, opacity: 0 },
    ], { duration: 700 + Math.random() * 400, easing: 'cubic-bezier(.16,1,.3,1)', fill: 'forwards' })
      .onfinish = () => p.remove();
  }
}

// ═══════════════════════════════════════════════════════════
// SCROLL REVEALS (cards, pillars, tools, timeline)
// ═══════════════════════════════════════════════════════════
function makeObserver(selector, stagger = 80, threshold = .15) {
  const obs = new IntersectionObserver(entries => {
    entries.forEach(e => {
      if (!e.isIntersecting) return;
      const siblings = [...e.target.parentElement.querySelectorAll(selector)];
      const idx = siblings.indexOf(e.target);
      setTimeout(() => e.target.classList.add('visible'), idx * stagger);
      obs.unobserve(e.target);
    });
  }, { threshold });
  document.querySelectorAll(selector).forEach(el => obs.observe(el));
}

makeObserver('.about-card', 120);
makeObserver('.pillar-card', 100);
makeObserver('.tool-card', 60);
makeObserver('.timeline-item', 140);

// Trigger progress bars when pillar cards appear
const progressObs = new IntersectionObserver(entries => {
  entries.forEach(e => {
    if (!e.isIntersecting) return;
    const bar = e.target.querySelector('.progress-bar');
    if (bar) bar.style.width = bar.dataset.width + '%';
    progressObs.unobserve(e.target);
  });
}, { threshold: .5 });
document.querySelectorAll('.pillar-card').forEach(c => progressObs.observe(c));

// Trigger tool bars
const toolBarObs = new IntersectionObserver(entries => {
  entries.forEach(e => {
    if (!e.isIntersecting) return;
    const bar = e.target.querySelector('.tool-bar div');
    if (bar) bar.style.width = bar.style.width; // force repaint via visible class
    toolBarObs.unobserve(e.target);
  });
}, { threshold: .3 });
document.querySelectorAll('.tool-card').forEach(c => toolBarObs.observe(c));

// ═══════════════════════════════════════════════════════════
// 3D TILT CARDS
// ═══════════════════════════════════════════════════════════
document.querySelectorAll('.tilt-card').forEach(card => {
  const shine = card.querySelector('.card-shine');
  let raf;

  card.addEventListener('mousemove', e => {
    cancelAnimationFrame(raf);
    raf = requestAnimationFrame(() => {
      const rect = card.getBoundingClientRect();
      const x = (e.clientX - rect.left) / rect.width  - .5;
      const y = (e.clientY - rect.top)  / rect.height - .5;
      const tiltX = y * -14;
      const tiltY = x *  14;
      card.style.transform = `perspective(800px) rotateX(${tiltX}deg) rotateY(${tiltY}deg) translateZ(4px)`;
      if (shine) {
        const sx = (e.clientX - rect.left) / rect.width  * 100;
        const sy = (e.clientY - rect.top)  / rect.height * 100;
        shine.style.background = `radial-gradient(circle at ${sx}% ${sy}%, rgba(255,255,255,.1), transparent 60%)`;
        shine.style.opacity = '1';
      }
    });
  });

  card.addEventListener('mouseleave', () => {
    cancelAnimationFrame(raf);
    card.style.transform = '';
    if (shine) { shine.style.opacity = '0'; }
  });
});

// ═══════════════════════════════════════════════════════════
// MAGNETIC BUTTONS
// ═══════════════════════════════════════════════════════════
document.querySelectorAll('.magnetic').forEach(el => {
  el.addEventListener('mousemove', e => {
    const rect = el.getBoundingClientRect();
    const cx = rect.left + rect.width  / 2;
    const cy = rect.top  + rect.height / 2;
    const dx = (e.clientX - cx) * .35;
    const dy = (e.clientY - cy) * .35;
    el.style.transform = `translate(${dx}px, ${dy}px)`;
  });
  el.addEventListener('mouseleave', () => {
    el.style.transform = '';
  });
});

// ═══════════════════════════════════════════════════════════
// TOOLS FILTER
// ═══════════════════════════════════════════════════════════
document.querySelectorAll('.filter-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    const filter = btn.dataset.filter;
    document.querySelectorAll('.tool-card').forEach((card, i) => {
      const match = filter === 'all' || card.dataset.category === filter;
      if (match) {
        card.classList.remove('hidden');
        setTimeout(() => card.classList.add('visible'), i * 40);
      } else {
        card.classList.add('hidden');
      }
    });
  });
});

// ═══════════════════════════════════════════════════════════
// MOUSE PARALLAX ON HERO
// ═══════════════════════════════════════════════════════════
const heroContent = document.getElementById('heroContent');
document.getElementById('hero')?.addEventListener('mousemove', e => {
  const w = window.innerWidth, h = window.innerHeight;
  const x = (e.clientX / w - .5) * 20;
  const y = (e.clientY / h - .5) * 12;
  heroContent.style.transform = `translate(${x * .3}px, ${y * .3}px)`;
  document.getElementById('neuralCanvas').style.transform = `translate(${-x * .15}px, ${-y * .15}px)`;
});
document.getElementById('hero')?.addEventListener('mouseleave', () => {
  heroContent.style.transform = '';
  document.getElementById('neuralCanvas').style.transform = '';
});

// ═══════════════════════════════════════════════════════════
// NEWSLETTER FORM
// ═══════════════════════════════════════════════════════════
document.getElementById('newsletterForm')?.addEventListener('submit', e => {
  e.preventDefault();
  const input = document.getElementById('emailInput');
  const msg   = document.getElementById('formMsg');
  if (!input.value) return;
  msg.textContent = `✓ You're in — welcome, ${input.value.split('@')[0]}!`;
  input.value = '';
  setTimeout(() => { msg.textContent = ''; }, 5000);
});

// ═══════════════════════════════════════════════════════════
// BACKGROUND PARTICLE CANVAS
// ═══════════════════════════════════════════════════════════
(function () {
  const canvas = document.getElementById('particleCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  let W, H, particles = [];

  function resize() {
    W = canvas.width  = window.innerWidth;
    H = canvas.height = window.innerHeight;
  }

  class Particle {
    constructor() { this.reset(); }
    reset() {
      this.x  = Math.random() * W;
      this.y  = Math.random() * H;
      this.vx = (Math.random() - .5) * .4;
      this.vy = (Math.random() - .5) * .4;
      this.r  = Math.random() * 1.5 + .5;
      this.a  = Math.random() * .4 + .1;
      this.hue = 220 + Math.random() * 60;
    }
    update() {
      this.x += this.vx;
      this.y += this.vy;
      if (this.x < 0 || this.x > W || this.y < 0 || this.y > H) this.reset();
    }
    draw() {
      ctx.beginPath();
      ctx.arc(this.x, this.y, this.r, 0, Math.PI * 2);
      ctx.fillStyle = `hsla(${this.hue},80%,70%,${this.a})`;
      ctx.fill();
    }
  }

  function init() { particles = Array.from({ length: 80 }, () => new Particle()); }

  function drawConnections() {
    for (let i = 0; i < particles.length; i++) {
      for (let j = i + 1; j < particles.length; j++) {
        const dx = particles[i].x - particles[j].x;
        const dy = particles[i].y - particles[j].y;
        const d  = Math.hypot(dx, dy);
        if (d < 120) {
          ctx.strokeStyle = `rgba(99,102,241,${(1 - d / 120) * .15})`;
          ctx.lineWidth = 1;
          ctx.beginPath();
          ctx.moveTo(particles[i].x, particles[i].y);
          ctx.lineTo(particles[j].x, particles[j].y);
          ctx.stroke();
        }
      }
    }
  }

  function loop() {
    ctx.clearRect(0, 0, W, H);
    drawConnections();
    particles.forEach(p => { p.update(); p.draw(); });
    requestAnimationFrame(loop);
  }

  window.addEventListener('resize', () => { resize(); init(); });
  resize(); init(); loop();
})();

// ═══════════════════════════════════════════════════════════
// HERO GRID CANVAS
// ═══════════════════════════════════════════════════════════
(function () {
  const canvas = document.getElementById('heroGrid');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');

  function resize() {
    canvas.width  = canvas.offsetWidth;
    canvas.height = canvas.offsetHeight;
  }

  let offset = 0;
  function draw() {
    const W = canvas.width, H = canvas.height;
    ctx.clearRect(0, 0, W, H);
    const step = 60;
    offset = (offset + .3) % step;
    ctx.strokeStyle = 'rgba(99,102,241,.08)';
    ctx.lineWidth = 1;
    for (let x = -step + offset % step; x < W + step; x += step) {
      ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, H); ctx.stroke();
    }
    for (let y = -step + offset % step; y < H + step; y += step) {
      ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(W, y); ctx.stroke();
    }
    requestAnimationFrame(draw);
  }

  const ro = new ResizeObserver(resize);
  ro.observe(canvas.parentElement);
  resize(); draw();
})();

// ═══════════════════════════════════════════════════════════
// NEURAL NETWORK CANVAS (hero right panel)
// ═══════════════════════════════════════════════════════════
(function () {
  const canvas = document.getElementById('neuralCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const NODES = 44, CONN = 65;
  let W, H, nodes = [], edges = [];

  function resize() {
    W = canvas.width  = canvas.offsetWidth;
    H = canvas.height = canvas.offsetHeight;
    init();
  }

  function rr(a, b) { return a + Math.random() * (b - a); }

  function init() {
    nodes = Array.from({ length: NODES }, () => ({
      x: rr(.05, .95) * W, y: rr(.05, .95) * H,
      vx: rr(-.25, .25), vy: rr(-.25, .25),
      r: rr(2, 4.5), pulse: Math.random() * Math.PI * 2,
      hue: 230 + Math.random() * 60,
    }));
    edges = Array.from({ length: CONN }, () => {
      const a = Math.floor(Math.random() * NODES);
      let   b = Math.floor(Math.random() * NODES);
      while (b === a) b = Math.floor(Math.random() * NODES);
      return { a, b, progress: Math.random(), speed: rr(.004, .01), active: Math.random() > .35 };
    });
  }

  function draw() {
    ctx.clearRect(0, 0, W, H);

    // Edges
    edges.forEach(edge => {
      const na = nodes[edge.a], nb = nodes[edge.b];
      const dx = nb.x - na.x, dy = nb.y - na.y;
      const dist = Math.hypot(dx, dy);
      if (dist > 320) return;
      const alpha = (1 - dist / 320) * .2;
      ctx.strokeStyle = `rgba(99,102,241,${alpha})`;
      ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(na.x, na.y); ctx.lineTo(nb.x, nb.y); ctx.stroke();

      if (edge.active) {
        edge.progress += edge.speed;
        if (edge.progress > 1) { edge.progress = 0; edge.active = Math.random() > .25; }
        const px = na.x + dx * edge.progress;
        const py = na.y + dy * edge.progress;
        const g = ctx.createRadialGradient(px, py, 0, px, py, 8);
        g.addColorStop(0, `hsla(${na.hue},80%,70%,.9)`);
        g.addColorStop(1, 'transparent');
        ctx.fillStyle = g;
        ctx.beginPath(); ctx.arc(px, py, 8, 0, Math.PI * 2); ctx.fill();
      }
    });

    // Nodes
    nodes.forEach(n => {
      n.pulse += .022;
      const g = Math.sin(n.pulse) * .4 + .6;

      // Outer glow
      const grd = ctx.createRadialGradient(n.x, n.y, 0, n.x, n.y, n.r * 5);
      grd.addColorStop(0, `hsla(${n.hue},80%,65%,${.35 * g})`);
      grd.addColorStop(1, 'transparent');
      ctx.fillStyle = grd;
      ctx.beginPath(); ctx.arc(n.x, n.y, n.r * 5, 0, Math.PI * 2); ctx.fill();

      // Core
      ctx.fillStyle = `hsla(${n.hue},80%,80%,${.8 * g})`;
      ctx.beginPath(); ctx.arc(n.x, n.y, n.r, 0, Math.PI * 2); ctx.fill();

      n.x += n.vx; n.y += n.vy;
      if (n.x < 0 || n.x > W) n.vx *= -1;
      if (n.y < 0 || n.y > H) n.vy *= -1;
    });

    requestAnimationFrame(draw);
  }

  const ro = new ResizeObserver(() => { resize(); });
  ro.observe(canvas.parentElement);
  resize(); draw();
})();
