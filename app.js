'use strict';

// ── Custom Cursor ─────────────────────────────────────────────────────────────
const cursor      = document.getElementById('cursor');
const cursorTrail = document.getElementById('cursorTrail');
let mx = -200, my = -200, tx = -200, ty = -200;

document.addEventListener('mousemove', e => {
  mx = e.clientX;
  my = e.clientY;
  cursor.style.left = mx + 'px';
  cursor.style.top  = my + 'px';
});

(function trailLoop() {
  tx += (mx - tx) * 0.12;
  ty += (my - ty) * 0.12;
  cursorTrail.style.left = tx + 'px';
  cursorTrail.style.top  = ty + 'px';
  requestAnimationFrame(trailLoop);
})();

// ── Nav scroll ────────────────────────────────────────────────────────────────
const nav = document.getElementById('nav');
window.addEventListener('scroll', () => {
  nav.classList.toggle('scrolled', window.scrollY > 40);
}, { passive: true });

// ── Hamburger ─────────────────────────────────────────────────────────────────
const hamburger  = document.getElementById('hamburger');
const navLinks   = document.querySelector('.nav-links');
const navCta     = document.querySelector('.nav-cta');
hamburger.addEventListener('click', () => {
  hamburger.classList.toggle('open');
  navLinks.classList.toggle('mobile-open');
});

// inject mobile nav styles once
(function() {
  const style = document.createElement('style');
  style.textContent = `
    .nav-links.mobile-open {
      display: flex !important;
      flex-direction: column;
      position: fixed;
      top: 64px; left: 0; right: 0;
      background: rgba(6,7,13,.97);
      backdrop-filter: blur(20px);
      padding: 24px;
      gap: 20px;
      border-bottom: 1px solid rgba(255,255,255,.07);
      z-index: 999;
      animation: slideDown .3s cubic-bezier(.16,1,.3,1);
    }
    @keyframes slideDown {
      from { opacity:0; transform:translateY(-12px); }
      to   { opacity:1; transform:translateY(0); }
    }
  `;
  document.head.appendChild(style);
})();

// ── Neural Network Canvas ─────────────────────────────────────────────────────
(function initCanvas() {
  const canvas = document.getElementById('neuralCanvas');
  const ctx    = canvas.getContext('2d');
  let W, H, nodes, mouseX = 0, mouseY = 0;

  const NODE_COUNT  = 80;
  const CONNECT_DST = 160;
  const MOUSE_PULL  = 120;

  function resize() {
    W = canvas.width  = canvas.offsetWidth;
    H = canvas.height = canvas.offsetHeight;
  }

  function makeNode() {
    return {
      x:   Math.random() * W,
      y:   Math.random() * H,
      vx: (Math.random() - .5) * .45,
      vy: (Math.random() - .5) * .45,
      r:   Math.random() * 2.5 + 1,
      alpha: Math.random() * .5 + .3,
    };
  }

  function init() {
    resize();
    nodes = Array.from({ length: NODE_COUNT }, makeNode);
  }

  function draw() {
    ctx.clearRect(0, 0, W, H);

    for (let i = 0; i < nodes.length; i++) {
      const n = nodes[i];

      // mouse attraction
      const dx = mouseX - n.x, dy = mouseY - n.y;
      const dist = Math.sqrt(dx*dx + dy*dy);
      if (dist < MOUSE_PULL) {
        const f = (1 - dist / MOUSE_PULL) * .012;
        n.vx += dx * f;
        n.vy += dy * f;
      }

      n.vx *= .985; n.vy *= .985;
      n.x += n.vx; n.y += n.vy;

      if (n.x < 0)  { n.x = 0;  n.vx *= -1; }
      if (n.x > W)  { n.x = W;  n.vx *= -1; }
      if (n.y < 0)  { n.y = 0;  n.vy *= -1; }
      if (n.y > H)  { n.y = H;  n.vy *= -1; }

      // connections
      for (let j = i + 1; j < nodes.length; j++) {
        const m   = nodes[j];
        const edx = n.x - m.x, edy = n.y - m.y;
        const len = Math.sqrt(edx*edx + edy*edy);
        if (len < CONNECT_DST) {
          const alpha = (1 - len / CONNECT_DST) * .35;
          const pct   = i / nodes.length;
          const r = Math.round(124 + (6-124)*pct);
          const g = Math.round(58  + (182-58)*pct);
          const b = Math.round(237 + (212-237)*pct);
          ctx.beginPath();
          ctx.moveTo(n.x, n.y);
          ctx.lineTo(m.x, m.y);
          ctx.strokeStyle = `rgba(${r},${g},${b},${alpha})`;
          ctx.lineWidth   = .8;
          ctx.stroke();
        }
      }

      // node dot
      const g = ctx.createRadialGradient(n.x, n.y, 0, n.x, n.y, n.r * 3);
      g.addColorStop(0, `rgba(167,139,250,${n.alpha})`);
      g.addColorStop(1, 'rgba(167,139,250,0)');
      ctx.beginPath();
      ctx.arc(n.x, n.y, n.r * 3, 0, Math.PI * 2);
      ctx.fillStyle = g;
      ctx.fill();
    }

    requestAnimationFrame(draw);
  }

  canvas.addEventListener('mousemove', e => {
    const rect = canvas.getBoundingClientRect();
    mouseX = e.clientX - rect.left;
    mouseY = e.clientY - rect.top;
  });

  window.addEventListener('resize', () => { resize(); }, { passive: true });
  init();
  draw();
})();

// ── Typed Text ────────────────────────────────────────────────────────────────
(function initTyped() {
  const el    = document.getElementById('typedText');
  const words = ['Intelligence', 'Neural Systems', 'LLM Agents', 'ML Pipelines', 'the Future'];
  let wi = 0, ci = 0, deleting = false;
  let speed = 80;

  function tick() {
    const word    = words[wi];
    const display = deleting ? word.slice(0, ci--) : word.slice(0, ci++);
    el.textContent = display;

    if (!deleting && ci > word.length) {
      deleting = true;
      speed = 2000; // pause before delete
    } else if (deleting && ci < 0) {
      deleting = false;
      ci = 0;
      wi = (wi + 1) % words.length;
      speed = 80;
    } else {
      speed = deleting ? 45 : 80;
    }

    setTimeout(tick, speed);
  }
  setTimeout(tick, 800);
})();

// ── Scroll Reveal ─────────────────────────────────────────────────────────────
(function initReveal() {
  const els = document.querySelectorAll('.reveal-up, .reveal-left, .reveal-right');

  const io = new IntersectionObserver(entries => {
    entries.forEach(e => {
      if (!e.isIntersecting) return;
      const delay = parseInt(e.target.dataset.delay || '0', 10);
      setTimeout(() => e.target.classList.add('in-view'), delay);
      io.unobserve(e.target);
    });
  }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });

  els.forEach(el => io.observe(el));
})();

// ── Counter Animation ─────────────────────────────────────────────────────────
(function initCounters() {
  const nums = document.querySelectorAll('.stat-num[data-target]');
  const fills = document.querySelectorAll('.stat-fill[data-pct]');

  const io = new IntersectionObserver(entries => {
    entries.forEach(e => {
      if (!e.isIntersecting) return;
      io.unobserve(e.target);

      // animate number
      const target  = parseInt(e.target.dataset.target, 10);
      const suffix  = e.target.dataset.suffix || '';
      const dur     = 1600;
      const start   = performance.now();

      function step(now) {
        const p = Math.min((now - start) / dur, 1);
        const eased = 1 - Math.pow(1 - p, 4);
        e.target.textContent = Math.round(eased * target) + suffix;
        if (p < 1) requestAnimationFrame(step);
      }
      requestAnimationFrame(step);
    });
  }, { threshold: 0.4 });

  nums.forEach(n => io.observe(n));

  // stat bars
  const barIo = new IntersectionObserver(entries => {
    entries.forEach(e => {
      if (!e.isIntersecting) return;
      barIo.unobserve(e.target);
      const pct = e.target.dataset.pct;
      setTimeout(() => { e.target.style.width = pct + '%'; }, 200);
    });
  }, { threshold: 0.4 });

  fills.forEach(f => barIo.observe(f));
})();

// ── Smooth Parallax on Hero Glow ─────────────────────────────────────────────
(function initParallax() {
  const g1 = document.querySelector('.hero-glow-1');
  const g2 = document.querySelector('.hero-glow-2');

  let ticking = false;
  window.addEventListener('scroll', () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => {
      const y = window.scrollY;
      if (g1) g1.style.transform = `translateY(${y * .2}px)`;
      if (g2) g2.style.transform = `translateY(${-y * .15}px)`;
      ticking = false;
    });
  }, { passive: true });
})();

// ── Service card tilt ────────────────────────────────────────────────────────
document.querySelectorAll('.service-card, .about-card, .stat-card').forEach(card => {
  card.addEventListener('mousemove', e => {
    const rect = card.getBoundingClientRect();
    const cx   = rect.left + rect.width  / 2;
    const cy   = rect.top  + rect.height / 2;
    const rx   = (e.clientY - cy) / (rect.height / 2) * -6;
    const ry   = (e.clientX - cx) / (rect.width  / 2) *  6;
    card.style.transform = `perspective(800px) rotateX(${rx}deg) rotateY(${ry}deg) translateY(-6px)`;
  });
  card.addEventListener('mouseleave', () => {
    card.style.transform = '';
  });
});

// ── Contact Form ──────────────────────────────────────────────────────────────
const form    = document.getElementById('contactForm');
const success = document.getElementById('formSuccess');

if (form) {
  form.addEventListener('submit', e => {
    e.preventDefault();
    const btn = form.querySelector('button[type="submit"]');
    btn.innerHTML = '<span>Sending…</span>';
    btn.disabled = true;

    setTimeout(() => {
      btn.innerHTML = '<span>Send Message</span><svg viewBox="0 0 24 24" fill="none"><path d="M5 12h14M12 5l7 7-7 7" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
      btn.disabled = false;
      success.classList.add('show');
      form.reset();
      setTimeout(() => success.classList.remove('show'), 5000);
    }, 1600);
  });
}

// ── Smooth anchor scroll ─────────────────────────────────────────────────────
document.querySelectorAll('a[href^="#"]').forEach(a => {
  a.addEventListener('click', e => {
    const id = a.getAttribute('href').slice(1);
    const target = document.getElementById(id);
    if (!target) return;
    e.preventDefault();
    target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    // close mobile menu
    hamburger.classList.remove('open');
    navLinks.classList.remove('mobile-open');
  });
});
