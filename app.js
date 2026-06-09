'use strict';

// ── LOADER ────────────────────────────────────────────────────────────────────
window.addEventListener('load', () => {
  setTimeout(() => {
    const loader = document.getElementById('loader');
    if (loader) {
      loader.classList.add('hidden');
      setTimeout(() => loader.remove(), 700);
    }
    initHeroReveal();
  }, 2400);
});

// ── CUSTOM CURSOR ─────────────────────────────────────────────────────────────
const cursor = document.querySelector('.cursor');
const follower = document.querySelector('.cursor-follower');
let mouseX = 0, mouseY = 0, followerX = 0, followerY = 0;

document.addEventListener('mousemove', e => {
  mouseX = e.clientX;
  mouseY = e.clientY;
  if (cursor) { cursor.style.left = mouseX + 'px'; cursor.style.top = mouseY + 'px'; }
});

function animateFollower() {
  followerX += (mouseX - followerX) * 0.12;
  followerY += (mouseY - followerY) * 0.12;
  if (follower) { follower.style.left = followerX + 'px'; follower.style.top = followerY + 'px'; }
  requestAnimationFrame(animateFollower);
}
animateFollower();

document.querySelectorAll('a, button, .class-card, .pricing-card, .trainer-card, .gallery-item').forEach(el => {
  el.addEventListener('mouseenter', () => {
    if (cursor)   cursor.classList.add('big');
    if (follower) follower.classList.add('big');
  });
  el.addEventListener('mouseleave', () => {
    if (cursor)   cursor.classList.remove('big');
    if (follower) follower.classList.remove('big');
  });
});

// ── NAVBAR SCROLL ─────────────────────────────────────────────────────────────
const navbar = document.getElementById('navbar');
window.addEventListener('scroll', () => {
  if (navbar) navbar.classList.toggle('scrolled', window.scrollY > 60);
  if (backToTop) backToTop.classList.toggle('visible', window.scrollY > 400);
}, { passive: true });

// ── HAMBURGER MENU ────────────────────────────────────────────────────────────
const hamburger  = document.getElementById('hamburger');
const mobileMenu = document.getElementById('mobileMenu');

if (hamburger && mobileMenu) {
  hamburger.addEventListener('click', () => {
    const open = mobileMenu.classList.toggle('open');
    hamburger.classList.toggle('open', open);
    document.body.style.overflow = open ? 'hidden' : '';
  });
  mobileMenu.querySelectorAll('a').forEach(link => {
    link.addEventListener('click', () => {
      mobileMenu.classList.remove('open');
      hamburger.classList.remove('open');
      document.body.style.overflow = '';
    });
  });
}

// ── PARTICLES ─────────────────────────────────────────────────────────────────
function createParticles() {
  const container = document.getElementById('particles');
  if (!container) return;
  const count = 40;
  for (let i = 0; i < count; i++) {
    const p = document.createElement('div');
    p.className = 'particle';
    const size = Math.random() * 4 + 1;
    p.style.cssText = `
      width: ${size}px;
      height: ${size}px;
      left: ${Math.random() * 100}%;
      top: ${Math.random() * 100 + 100}%;
      animation-duration: ${Math.random() * 12 + 8}s;
      animation-delay: ${Math.random() * -15}s;
      opacity: ${Math.random() * 0.6 + 0.2};
    `;
    container.appendChild(p);
  }
}
createParticles();

// ── HERO STAT COUNTER (on load) ───────────────────────────────────────────────
function animateValue(el, target, duration, suffix) {
  const start = performance.now();
  const update = (now) => {
    const elapsed = now - start;
    const progress = Math.min(elapsed / duration, 1);
    const ease = 1 - Math.pow(1 - progress, 3);
    const value = Math.round(ease * target);
    el.textContent = value >= 1000 ? value.toLocaleString() : value;
    if (progress < 1) requestAnimationFrame(update);
    else el.textContent = target >= 1000 ? target.toLocaleString() : target;
  };
  requestAnimationFrame(update);
}

function initHeroReveal() {
  document.querySelectorAll('.hero .reveal-up').forEach((el, i) => {
    setTimeout(() => el.classList.add('revealed'), i * 120);
  });
  setTimeout(() => {
    document.querySelectorAll('.hero .stat-num').forEach(el => {
      animateValue(el, parseInt(el.dataset.target), 1800, '');
    });
  }, 600);
}

// ── SCROLL REVEAL ─────────────────────────────────────────────────────────────
const revealEls = document.querySelectorAll('.reveal-up, .reveal-left, .reveal-right');
const revealObs = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.classList.add('revealed');
      revealObs.unobserve(entry.target);
    }
  });
}, { threshold: 0.12, rootMargin: '0px 0px -60px 0px' });

revealEls.forEach(el => {
  if (!el.closest('.hero')) revealObs.observe(el);
});

// ── COUNTER SECTION ───────────────────────────────────────────────────────────
const counterObs = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.querySelectorAll('.counter-num').forEach(el => {
        animateValue(el, parseInt(el.dataset.target), 2200, '');
      });
      counterObs.unobserve(entry.target);
    }
  });
}, { threshold: 0.3 });

const counterSection = document.querySelector('.counter-section');
if (counterSection) counterObs.observe(counterSection);

// ── PARALLAX ──────────────────────────────────────────────────────────────────
const parallaxEls = document.querySelectorAll('.parallax');
window.addEventListener('scroll', () => {
  const scrollY = window.scrollY;
  parallaxEls.forEach(el => {
    const speed = parseFloat(el.dataset.speed) || 0.2;
    const rect  = el.getBoundingClientRect();
    const offsetY = (rect.top + scrollY) * speed;
    el.style.transform = `translateY(${offsetY * -0.15}px)`;
  });
}, { passive: true });

// ── PRICING TOGGLE ────────────────────────────────────────────────────────────
const toggleSwitch = document.getElementById('toggleSwitch');
let isAnnual = false;

if (toggleSwitch) {
  toggleSwitch.addEventListener('click', () => {
    isAnnual = !isAnnual;
    toggleSwitch.classList.toggle('on', isAnnual);
    document.querySelectorAll('.price-num').forEach(el => {
      const target = parseInt(isAnnual ? el.dataset.annual : el.dataset.monthly);
      animateValue(el, target, 600, '');
    });
  });
}

// ── TESTIMONIALS SLIDER ───────────────────────────────────────────────────────
const track     = document.getElementById('testimonialsTrack');
const dotsWrap  = document.getElementById('testiDots');
const prevBtn   = document.getElementById('testiPrev');
const nextBtn   = document.getElementById('testiNext');

if (track) {
  const cards      = track.querySelectorAll('.testi-card');
  const perView    = () => window.innerWidth <= 768 ? 1 : 3;
  let current      = 0;
  let autoTimer;

  function totalSlides() {
    return Math.ceil(cards.length / perView());
  }

  function buildDots() {
    if (!dotsWrap) return;
    dotsWrap.innerHTML = '';
    for (let i = 0; i < totalSlides(); i++) {
      const dot = document.createElement('button');
      dot.className = 'testi-dot' + (i === current ? ' active' : '');
      dot.setAttribute('aria-label', `Slide ${i + 1}`);
      dot.addEventListener('click', () => goTo(i));
      dotsWrap.appendChild(dot);
    }
  }

  function goTo(idx) {
    current = (idx + totalSlides()) % totalSlides();
    const cardWidth  = cards[0].offsetWidth + 24;
    const offset     = current * perView() * cardWidth;
    track.style.transform = `translateX(-${offset}px)`;
    dotsWrap && dotsWrap.querySelectorAll('.testi-dot').forEach((d, i) => {
      d.classList.toggle('active', i === current);
    });
  }

  function startAuto() {
    autoTimer = setInterval(() => goTo(current + 1), 4500);
  }
  function stopAuto() { clearInterval(autoTimer); }

  if (prevBtn) prevBtn.addEventListener('click', () => { stopAuto(); goTo(current - 1); startAuto(); });
  if (nextBtn) nextBtn.addEventListener('click', () => { stopAuto(); goTo(current + 1); startAuto(); });

  let touchStartX = 0;
  track.addEventListener('touchstart', e => { touchStartX = e.touches[0].clientX; stopAuto(); }, { passive: true });
  track.addEventListener('touchend',   e => {
    const diff = touchStartX - e.changedTouches[0].clientX;
    if (Math.abs(diff) > 50) goTo(current + (diff > 0 ? 1 : -1));
    startAuto();
  });

  window.addEventListener('resize', () => { buildDots(); goTo(current); });
  buildDots();
  startAuto();
}

// ── BACK TO TOP ───────────────────────────────────────────────────────────────
const backToTop = document.getElementById('backToTop');
if (backToTop) {
  backToTop.addEventListener('click', () => window.scrollTo({ top: 0, behavior: 'smooth' }));
}

// ── CONTACT FORM ──────────────────────────────────────────────────────────────
const contactForm = document.getElementById('contactForm');
if (contactForm) {
  contactForm.addEventListener('submit', e => {
    e.preventDefault();
    const btn    = contactForm.querySelector('.submit-btn');
    const text   = btn.querySelector('.btn-text');
    const loader = btn.querySelector('.btn-loader');
    btn.disabled = true;
    text.style.display  = 'none';
    loader.style.display = 'inline';
    setTimeout(() => {
      contactForm.closest('.contact-form-wrap').innerHTML = `
        <div class="form-success">
          <h3>YOU'RE IN.</h3>
          <p>Welcome to IRONFORGE. We'll be in touch within 24 hours.<br>
          Get ready to forge your legend.</p>
        </div>`;
    }, 1800);
  });
}

// ── SMOOTH NAV SCROLL ─────────────────────────────────────────────────────────
document.querySelectorAll('a[href^="#"]').forEach(link => {
  link.addEventListener('click', e => {
    const id = link.getAttribute('href');
    if (id === '#') return;
    const target = document.querySelector(id);
    if (target) {
      e.preventDefault();
      const offset = target.getBoundingClientRect().top + window.scrollY - 80;
      window.scrollTo({ top: offset, behavior: 'smooth' });
    }
  });
});

// ── HERO TITLE GLITCH ON HOVER ────────────────────────────────────────────────
const heroTitle = document.querySelector('.hero-title');
if (heroTitle) {
  heroTitle.addEventListener('mouseenter', () => {
    heroTitle.style.animation = 'none';
    heroTitle.querySelectorAll('.line').forEach((line, i) => {
      line.style.transform = `skewX(${(Math.random() - 0.5) * 6}deg)`;
      setTimeout(() => { line.style.transform = ''; }, 200 + i * 60);
    });
  });
}

// ── MAGNETIC BUTTONS ─────────────────────────────────────────────────────────
document.querySelectorAll('.btn-primary, .btn-ghost, .btn-nav').forEach(btn => {
  btn.addEventListener('mousemove', e => {
    const rect = btn.getBoundingClientRect();
    const x = e.clientX - rect.left - rect.width  / 2;
    const y = e.clientY - rect.top  - rect.height / 2;
    btn.style.transform = `translate(${x * 0.18}px, ${y * 0.18}px) translateY(-3px)`;
  });
  btn.addEventListener('mouseleave', () => {
    btn.style.transform = '';
  });
});

// ── SCROLL PROGRESS BAR ───────────────────────────────────────────────────────
const progressBar = document.createElement('div');
progressBar.style.cssText = `
  position: fixed; top: 0; left: 0; height: 2px; width: 0%;
  background: var(--red, #e63025); z-index: 9999;
  transition: width 0.1s linear;
  box-shadow: 0 0 8px rgba(230,48,37,0.8);
`;
document.body.appendChild(progressBar);

window.addEventListener('scroll', () => {
  const scrollTop = window.scrollY;
  const docHeight = document.documentElement.scrollHeight - window.innerHeight;
  progressBar.style.width = ((scrollTop / docHeight) * 100) + '%';
}, { passive: true });
