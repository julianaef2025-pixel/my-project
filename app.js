'use strict';

/* ── Custom Cursor ─────────────────────────────────────────── */
const cursor     = document.getElementById('cursor');
const cursorRing = document.getElementById('cursorRing');

let mouseX = 0, mouseY = 0, ringX = 0, ringY = 0;

document.addEventListener('mousemove', e => {
  mouseX = e.clientX;
  mouseY = e.clientY;
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

/* ── Navbar scroll ─────────────────────────────────────────── */
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

/* ── Particle Canvas ───────────────────────────────────────── */
(function initParticles() {
  const canvas = document.getElementById('particleCanvas');
  const ctx    = canvas.getContext('2d');
  let W, H;

  function resize() {
    W = canvas.width  = canvas.offsetWidth;
    H = canvas.height = canvas.offsetHeight;
  }
  resize();
  window.addEventListener('resize', resize);

  const COUNT = window.innerWidth < 768 ? 40 : 90;
  // Light/white particles since hero is dark gradient
  const COLORS = [
    'rgba(255,255,255,',
    'rgba(255,209,102,',
    'rgba(0,212,168,',
    'rgba(255,107,53,',
  ];

  const particles = Array.from({ length: COUNT }, () => ({
    x: Math.random() * (window.innerWidth || 1200),
    y: Math.random() * 800,
    r: Math.random() * 2.5 + 0.6,
    vx: (Math.random() - .5) * .3,
    vy: (Math.random() - .5) * .3,
    alpha: Math.random() * .5 + .15,
    color: COLORS[Math.floor(Math.random() * COLORS.length)],
    pulse: Math.random() * Math.PI * 2,
  }));

  function draw() {
    ctx.clearRect(0, 0, W, H);

    for (let i = 0; i < particles.length; i++) {
      for (let j = i + 1; j < particles.length; j++) {
        const dx = particles[i].x - particles[j].x;
        const dy = particles[i].y - particles[j].y;
        const d  = Math.sqrt(dx * dx + dy * dy);
        if (d < 110) {
          ctx.beginPath();
          ctx.moveTo(particles[i].x, particles[i].y);
          ctx.lineTo(particles[j].x, particles[j].y);
          ctx.strokeStyle = `rgba(255,255,255,${(1 - d / 110) * .15})`;
          ctx.lineWidth   = .7;
          ctx.stroke();
        }
      }
    }

    particles.forEach(p => {
      p.pulse += .018;
      const a = p.alpha * (.7 + .3 * Math.sin(p.pulse));
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fillStyle = p.color + a + ')';
      ctx.fill();
      p.x += p.vx;
      p.y += p.vy;
      if (p.x < 0) p.x = W;
      if (p.x > W) p.x = 0;
      if (p.y < 0) p.y = H;
      if (p.y > H) p.y = 0;
    });

    requestAnimationFrame(draw);
  }
  draw();
})();

/* ── Typewriter ────────────────────────────────────────────── */
(function initTypewriter() {
  const el    = document.getElementById('typewriter');
  const words = ['English', 'Spanish', 'French', 'German', 'Japanese', 'Chinese', 'Italian', 'Portuguese'];
  let wi = 0, ci = 0, deleting = false;

  function tick() {
    const word = words[wi];
    el.textContent = deleting ? word.slice(0, ci--) : word.slice(0, ci++);

    if (!deleting && ci > word.length) { deleting = true; return setTimeout(tick, 1600); }
    if (deleting && ci < 0)           { deleting = false; ci = 0; wi = (wi + 1) % words.length; }

    setTimeout(tick, deleting ? 60 : 110);
  }
  tick();
})();

/* ── Scroll reveal ─────────────────────────────────────────── */
const revealObs = new IntersectionObserver(
  entries => entries.forEach(e => { if (e.isIntersecting) { e.target.classList.add('visible'); revealObs.unobserve(e.target); } }),
  { threshold: 0.12 }
);
document.querySelectorAll('.reveal').forEach(el => revealObs.observe(el));

/* ── Counters ──────────────────────────────────────────────── */
function animateCounter(el, target, suffix) {
  const start    = performance.now();
  const duration = 2000;
  function step(now) {
    const p = Math.min((now - start) / duration, 1);
    const e = 1 - Math.pow(1 - p, 3);
    el.textContent = Math.round(e * target).toLocaleString() + suffix;
    if (p < 1) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
}
const counterObs = new IntersectionObserver(
  entries => entries.forEach(e => {
    if (e.isIntersecting) {
      animateCounter(e.target, +e.target.dataset.target, e.target.dataset.suffix || '');
      counterObs.unobserve(e.target);
    }
  }),
  { threshold: 0.3 }
);
document.querySelectorAll('.stat-number[data-target]').forEach(el => counterObs.observe(el));

/* ── 3D Tilt on tutor cards ────────────────────────────────── */
document.querySelectorAll('.tutor-card').forEach(card => {
  const inner = card.querySelector('.tutor-card-inner');
  card.addEventListener('mousemove', e => {
    const r  = card.getBoundingClientRect();
    const dx = (e.clientX - r.left - r.width  / 2) / (r.width  / 2);
    const dy = (e.clientY - r.top  - r.height / 2) / (r.height / 2);
    inner.style.transform    = `perspective(800px) rotateX(${-dy*8}deg) rotateY(${dx*8}deg) scale(1.02)`;
    inner.style.transition   = 'none';
  });
  card.addEventListener('mouseleave', () => {
    inner.style.transition   = 'transform .5s ease';
    inner.style.transform    = '';
  });
});

/* ── Magnetic buttons ──────────────────────────────────────── */
document.querySelectorAll('.magnetic').forEach(btn => {
  btn.addEventListener('mousemove', e => {
    const r  = btn.getBoundingClientRect();
    const dx = (e.clientX - r.left - r.width  / 2) * .25;
    const dy = (e.clientY - r.top  - r.height / 2) * .25;
    btn.style.transform = `translate(${dx}px,${dy}px)`;
  });
  btn.addEventListener('mouseleave', () => {
    btn.style.transition = 'transform .5s cubic-bezier(.4,0,.2,1)';
    btn.style.transform  = '';
    setTimeout(() => btn.style.transition = '', 500);
  });
});

/* ── Parallax hero on scroll ───────────────────────────────── */
const heroContent = document.querySelector('.hero-content');
window.addEventListener('scroll', () => {
  if (window.scrollY < window.innerHeight && heroContent) {
    heroContent.style.transform = `translateY(${window.scrollY * .1}px)`;
  }
}, { passive: true });

/* ── Smooth scroll ─────────────────────────────────────────── */
document.querySelectorAll('a[href^="#"]').forEach(link => {
  link.addEventListener('click', e => {
    const target = document.querySelector(link.getAttribute('href'));
    if (target) { e.preventDefault(); target.scrollIntoView({ behavior: 'smooth', block: 'start' }); }
  });
});
