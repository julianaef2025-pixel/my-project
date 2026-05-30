'use strict';

/* ── Custom Cursor ─────────────────────────────────────────── */
const cursor     = document.getElementById('cursor');
const cursorRing = document.getElementById('cursorRing');
let mouseX = 0, mouseY = 0, ringX = 0, ringY = 0;

document.addEventListener('mousemove', e => {
  mouseX = e.clientX; mouseY = e.clientY;
  cursor.style.left = mouseX + 'px';
  cursor.style.top  = mouseY + 'px';
});
(function animateRing() {
  ringX += (mouseX - ringX) * 0.12;
  ringY += (mouseY - ringY) * 0.12;
  cursorRing.style.left = ringX + 'px';
  cursorRing.style.top  = ringY + 'px';
  requestAnimationFrame(animateRing);
})();
document.querySelectorAll('a, button, .lang-card, .tutor-card, .why-card, .testimonial-card').forEach(el => {
  el.addEventListener('mouseenter', () => { cursor.classList.add('hovered'); cursorRing.classList.add('hovered'); });
  el.addEventListener('mouseleave', () => { cursor.classList.remove('hovered'); cursorRing.classList.remove('hovered'); });
});

/* ── Navbar ────────────────────────────────────────────────── */
const navbar = document.getElementById('navbar');
window.addEventListener('scroll', () => {
  navbar.classList.toggle('scrolled', window.scrollY > 60);
}, { passive: true });

/* ── Mobile menu ───────────────────────────────────────────── */
const hamburger  = document.getElementById('hamburger');
const mobileMenu = document.getElementById('mobileMenu');
hamburger.addEventListener('click', () => {
  hamburger.classList.toggle('open');
  mobileMenu.classList.toggle('open');
});
mobileMenu.querySelectorAll('a').forEach(a => {
  a.addEventListener('click', () => {
    hamburger.classList.remove('open');
    mobileMenu.classList.remove('open');
  });
});

/* ── Typewriter ────────────────────────────────────────────── */
const twEl  = document.getElementById('typewriter');
const words = ['English','Spanish','French','German','Japanese','Chinese','Italian','Portuguese'];
let wi = 0, ci = 0, deleting = false;
function tick() {
  const word = words[wi];
  twEl.textContent = deleting ? word.slice(0, ci--) : word.slice(0, ci++);
  if (!deleting && ci > word.length) { deleting = true; return setTimeout(tick, 1600); }
  if (deleting && ci < 0)           { deleting = false; ci = 0; wi = (wi + 1) % words.length; }
  setTimeout(tick, deleting ? 60 : 110);
}
tick();

/* ── Particles ─────────────────────────────────────────────── */
try {
  const canvas = document.getElementById('particleCanvas');
  const ctx    = canvas.getContext('2d');
  let W = 0, H = 0;

  function resizeCanvas() {
    W = canvas.width  = canvas.offsetWidth  || window.innerWidth;
    H = canvas.height = canvas.offsetHeight || window.innerHeight;
  }
  resizeCanvas();
  window.addEventListener('resize', resizeCanvas, { passive: true });

  const COUNT  = window.innerWidth < 768 ? 40 : 80;
  const COLORS = ['rgba(255,255,255,','rgba(255,209,102,','rgba(0,212,168,','rgba(255,107,53,'];
  const pts = Array.from({ length: COUNT }, () => ({
    x: Math.random() * W, y: Math.random() * H,
    r: Math.random() * 2.2 + 0.5,
    vx: (Math.random() - .5) * .28, vy: (Math.random() - .5) * .28,
    a: Math.random() * .45 + .15,
    col: COLORS[Math.floor(Math.random() * COLORS.length)],
    ph: Math.random() * Math.PI * 2,
  }));

  function drawParticles() {
    ctx.clearRect(0, 0, W, H);
    for (let i = 0; i < pts.length; i++) {
      for (let j = i + 1; j < pts.length; j++) {
        const dx = pts[i].x - pts[j].x, dy = pts[i].y - pts[j].y;
        const d = Math.sqrt(dx*dx + dy*dy);
        if (d < 110) {
          ctx.beginPath();
          ctx.moveTo(pts[i].x, pts[i].y);
          ctx.lineTo(pts[j].x, pts[j].y);
          ctx.strokeStyle = `rgba(255,255,255,${(1-d/110)*.13})`;
          ctx.lineWidth = .6; ctx.stroke();
        }
      }
    }
    pts.forEach(p => {
      p.ph += .018;
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r, 0, Math.PI*2);
      ctx.fillStyle = p.col + (p.a * (.7 + .3*Math.sin(p.ph))) + ')';
      ctx.fill();
      p.x += p.vx; p.y += p.vy;
      if (p.x < 0) p.x = W; if (p.x > W) p.x = 0;
      if (p.y < 0) p.y = H; if (p.y > H) p.y = 0;
    });
    requestAnimationFrame(drawParticles);
  }
  drawParticles();
} catch(e) { /* particles are decorative — safe to skip */ }

/* ── Scroll reveal ─────────────────────────────────────────── */
const reveals = document.querySelectorAll('.reveal');

// Immediate fallback: show everything visible in viewport on load
function checkVisible() {
  reveals.forEach(el => {
    const rect = el.getBoundingClientRect();
    if (rect.top < window.innerHeight * 1.1) {
      el.classList.add('visible');
    }
  });
}
checkVisible();
window.addEventListener('scroll', checkVisible, { passive: true });

// Also use IntersectionObserver for smoother staggered reveals
if ('IntersectionObserver' in window) {
  const obs = new IntersectionObserver(entries => {
    entries.forEach(e => { if (e.isIntersecting) { e.target.classList.add('visible'); obs.unobserve(e.target); } });
  }, { threshold: 0.08 });
  reveals.forEach(el => obs.observe(el));
}

/* ── Counters ──────────────────────────────────────────────── */
function runCounter(el) {
  const target = parseInt(el.dataset.target, 10);
  const suffix = el.dataset.suffix || '';
  const start  = performance.now();
  const dur    = 1800;
  function step(now) {
    const p = Math.min((now - start) / dur, 1);
    const e = 1 - Math.pow(1 - p, 3);
    el.textContent = Math.round(e * target).toLocaleString() + suffix;
    if (p < 1) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
}
if ('IntersectionObserver' in window) {
  const cobs = new IntersectionObserver(entries => {
    entries.forEach(e => { if (e.isIntersecting) { runCounter(e.target); cobs.unobserve(e.target); } });
  }, { threshold: 0.3 });
  document.querySelectorAll('.stat-number[data-target]').forEach(el => cobs.observe(el));
}

/* ── Tutor card 3-D tilt ───────────────────────────────────── */
document.querySelectorAll('.tutor-card').forEach(card => {
  const inner = card.querySelector('.tutor-card-inner');
  if (!inner) return;
  card.addEventListener('mousemove', e => {
    const r = card.getBoundingClientRect();
    const dx = (e.clientX - r.left - r.width/2)  / (r.width/2);
    const dy = (e.clientY - r.top  - r.height/2) / (r.height/2);
    inner.style.transition = 'none';
    inner.style.transform  = `perspective(800px) rotateX(${-dy*7}deg) rotateY(${dx*7}deg) scale(1.02)`;
  });
  card.addEventListener('mouseleave', () => {
    inner.style.transition = 'transform .5s ease';
    inner.style.transform  = '';
  });
});

/* ── Magnetic buttons ──────────────────────────────────────── */
document.querySelectorAll('.magnetic').forEach(btn => {
  btn.addEventListener('mousemove', e => {
    const r = btn.getBoundingClientRect();
    btn.style.transform = `translate(${(e.clientX-r.left-r.width/2)*.25}px,${(e.clientY-r.top-r.height/2)*.25}px)`;
  });
  btn.addEventListener('mouseleave', () => {
    btn.style.transition = 'transform .5s cubic-bezier(.4,0,.2,1)';
    btn.style.transform  = '';
    setTimeout(() => btn.style.transition = '', 500);
  });
});

/* ── Hero parallax ─────────────────────────────────────────── */
const heroContent = document.querySelector('.hero-content');
window.addEventListener('scroll', () => {
  if (heroContent && window.scrollY < window.innerHeight) {
    heroContent.style.transform = `translateY(${window.scrollY * .1}px)`;
  }
}, { passive: true });

/* ── Smooth scroll ─────────────────────────────────────────── */
document.querySelectorAll('a[href^="#"]').forEach(link => {
  link.addEventListener('click', e => {
    const t = document.querySelector(link.getAttribute('href'));
    if (t) { e.preventDefault(); t.scrollIntoView({ behavior: 'smooth' }); }
  });
});
