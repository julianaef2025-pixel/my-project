'use strict';

/* ── Preloader ─────────────────────────────────────────────── */
window.addEventListener('load', () => {
  setTimeout(() => {
    document.getElementById('preloader').classList.add('hidden');
  }, 900);
});

/* ── Custom Cursor ─────────────────────────────────────────── */
const cursor     = document.getElementById('cursor');
const cursorRing = document.getElementById('cursorRing');

let mouseX = 0, mouseY = 0;
let ringX  = 0, ringY  = 0;

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

document.querySelectorAll('a, button, .lang-card, .tutor-card, .why-card').forEach(el => {
  el.addEventListener('mouseenter', () => { cursor.classList.add('hovered'); cursorRing.classList.add('hovered'); });
  el.addEventListener('mouseleave', () => { cursor.classList.remove('hovered'); cursorRing.classList.remove('hovered'); });
});

/* ── Navbar scroll ─────────────────────────────────────────── */
const navbar = document.getElementById('navbar');
window.addEventListener('scroll', () => {
  navbar.classList.toggle('scrolled', window.scrollY > 40);
});

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

  let W, H, particles;

  function resize() {
    W = canvas.width  = canvas.offsetWidth;
    H = canvas.height = canvas.offsetHeight;
  }
  resize();
  window.addEventListener('resize', resize);

  const COUNT = window.innerWidth < 768 ? 50 : 110;
  const COLORS = ['rgba(100,64,251,', 'rgba(0,212,168,', 'rgba(155,120,255,'];

  function makeParticle() {
    const color = COLORS[Math.floor(Math.random() * COLORS.length)];
    return {
      x: Math.random() * W,
      y: Math.random() * H,
      r: Math.random() * 2.2 + 0.5,
      vx: (Math.random() - .5) * .35,
      vy: (Math.random() - .5) * .35,
      alpha: Math.random() * .6 + .2,
      color,
      pulse: Math.random() * Math.PI * 2,
    };
  }

  particles = Array.from({ length: COUNT }, makeParticle);

  function draw() {
    ctx.clearRect(0, 0, W, H);

    // connections
    for (let i = 0; i < particles.length; i++) {
      for (let j = i + 1; j < particles.length; j++) {
        const dx   = particles[i].x - particles[j].x;
        const dy   = particles[i].y - particles[j].y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < 120) {
          const a = (1 - dist / 120) * .2;
          ctx.beginPath();
          ctx.moveTo(particles[i].x, particles[i].y);
          ctx.lineTo(particles[j].x, particles[j].y);
          ctx.strokeStyle = `rgba(100,64,251,${a})`;
          ctx.lineWidth   = .6;
          ctx.stroke();
        }
      }
    }

    // dots
    particles.forEach(p => {
      p.pulse += .02;
      const pAlpha = p.alpha * (.7 + .3 * Math.sin(p.pulse));
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fillStyle = p.color + pAlpha + ')';
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

    if (!deleting && ci > word.length) {
      deleting = true;
      return setTimeout(tick, 1600);
    }
    if (deleting && ci < 0) {
      deleting = false;
      ci = 0;
      wi = (wi + 1) % words.length;
    }
    setTimeout(tick, deleting ? 60 : 110);
  }
  tick();
})();

/* ── Intersection Observer (reveal + counters) ─────────────── */
const revealObs = new IntersectionObserver(
  entries => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        revealObs.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.12 }
);
document.querySelectorAll('.reveal').forEach(el => revealObs.observe(el));

/* ── Counters ──────────────────────────────────────────────── */
function animateCounter(el, target, suffix) {
  const start = performance.now();
  const duration = 2000;

  function step(now) {
    const elapsed  = now - start;
    const progress = Math.min(elapsed / duration, 1);
    const ease     = 1 - Math.pow(1 - progress, 3); // ease-out cubic
    const value    = Math.round(ease * target);
    el.textContent = value.toLocaleString() + suffix;
    if (progress < 1) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
}

const counterObs = new IntersectionObserver(
  entries => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        const el     = entry.target;
        const target = parseInt(el.dataset.target, 10);
        const suffix = el.dataset.suffix || '';
        animateCounter(el, target, suffix);
        counterObs.unobserve(el);
      }
    });
  },
  { threshold: 0.3 }
);
document.querySelectorAll('.stat-number[data-target]').forEach(el => counterObs.observe(el));

/* ── 3D Tilt on tutor cards ────────────────────────────────── */
document.querySelectorAll('.tutor-card').forEach(card => {
  const inner = card.querySelector('.tutor-card-inner');

  card.addEventListener('mousemove', e => {
    const rect   = card.getBoundingClientRect();
    const cx     = rect.left + rect.width  / 2;
    const cy     = rect.top  + rect.height / 2;
    const dx     = (e.clientX - cx) / (rect.width  / 2);
    const dy     = (e.clientY - cy) / (rect.height / 2);
    const rotY   =  dx * 9;
    const rotX   = -dy * 9;
    inner.style.transform = `perspective(800px) rotateX(${rotX}deg) rotateY(${rotY}deg) scale(1.02)`;
  });

  card.addEventListener('mouseleave', () => {
    inner.style.transform = 'perspective(800px) rotateX(0) rotateY(0) scale(1)';
    inner.style.transition = 'transform .5s ease';
    setTimeout(() => inner.style.transition = '', 500);
  });
});

/* ── Magnetic buttons ──────────────────────────────────────── */
document.querySelectorAll('.magnetic').forEach(btn => {
  btn.addEventListener('mousemove', e => {
    const rect = btn.getBoundingClientRect();
    const cx   = rect.left + rect.width  / 2;
    const cy   = rect.top  + rect.height / 2;
    const dx   = (e.clientX - cx) * .28;
    const dy   = (e.clientY - cy) * .28;
    btn.style.transform = `translate(${dx}px, ${dy}px)`;
  });

  btn.addEventListener('mouseleave', () => {
    btn.style.transform = '';
    btn.style.transition = 'transform .5s cubic-bezier(.4,0,.2,1)';
    setTimeout(() => btn.style.transition = '', 500);
  });
});

/* ── Parallax hero on scroll ───────────────────────────────── */
const heroContent = document.querySelector('.hero-content');
const heroGlow1   = document.querySelector('.hero-glow-1');
const heroGlow2   = document.querySelector('.hero-glow-2');

window.addEventListener('scroll', () => {
  const scrollY = window.scrollY;
  if (scrollY < window.innerHeight) {
    if (heroContent) heroContent.style.transform = `translateY(${scrollY * .12}px)`;
    if (heroGlow1)   heroGlow1.style.transform   = `translateY(${scrollY * .06}px) scale(1)`;
    if (heroGlow2)   heroGlow2.style.transform   = `translateY(${-scrollY * .05}px) scale(1)`;
  }
}, { passive: true });

/* ── Smooth scroll for nav links ───────────────────────────── */
document.querySelectorAll('a[href^="#"]').forEach(link => {
  link.addEventListener('click', e => {
    const target = document.querySelector(link.getAttribute('href'));
    if (target) {
      e.preventDefault();
      target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  });
});

/* ── Language card shimmer on hover ─────────────────────────── */
document.querySelectorAll('.lang-card').forEach(card => {
  card.addEventListener('mousemove', e => {
    const rect = card.getBoundingClientRect();
    const x = ((e.clientX - rect.left) / rect.width)  * 100;
    const y = ((e.clientY - rect.top)  / rect.height) * 100;
    card.style.setProperty('--mx', x + '%');
    card.style.setProperty('--my', y + '%');
  });
});

/* ── Why card glow follow cursor ────────────────────────────── */
document.querySelectorAll('.why-card').forEach(card => {
  card.addEventListener('mousemove', e => {
    const rect = card.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    card.style.setProperty('--x', x + 'px');
    card.style.setProperty('--y', y + 'px');
    card.querySelector('::before');
  });
});
