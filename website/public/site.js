const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const nav = document.querySelector('.nav-wrap');

window.addEventListener('scroll', () => nav.classList.toggle('scrolled', window.scrollY > 30), { passive: true });

document.querySelectorAll('details').forEach((item) => {
  item.addEventListener('toggle', () => {
    if (!item.open) return;
    document.querySelectorAll('details').forEach((other) => {
      if (other !== item) other.open = false;
    });
  });
});

if (!reduceMotion && window.gsap && window.ScrollTrigger) {
  gsap.registerPlugin(ScrollTrigger);

  gsap.timeline({ defaults: { ease: 'power3.out' } })
    .from('.nav', { y: -30, opacity: 0, duration: .8 })
    .from('.hero-copy > *', { y: 35, opacity: 0, stagger: .1, duration: .9 }, '-=.45')
    .from('.sun-disc', { scale: .7, opacity: 0, duration: 1.2 }, '-=1')
    .from('.hero-character', { y: 80, scale: .86, opacity: 0, duration: 1.1 }, '-=.95')
    .from('.finder-card, .result-card, .orbit-file', { scale: .7, opacity: 0, stagger: .1, duration: .65 }, '-=.7');

  gsap.to('.hero-character', { y: -13, rotation: .6, duration: 2.2, repeat: -1, yoyo: true, ease: 'sine.inOut' });
  gsap.to('.orbit-one', { y: -18, x: 8, rotation: -5, duration: 2.4, repeat: -1, yoyo: true, ease: 'sine.inOut' });
  gsap.to('.orbit-two', { y: 15, x: -9, rotation: 15, duration: 2.8, repeat: -1, yoyo: true, ease: 'sine.inOut' });

  gsap.utils.toArray('.reveal').forEach((element) => {
    gsap.from(element.children, {
      scrollTrigger: { trigger: element, start: 'top 82%' },
      y: 45, opacity: 0, duration: .9, stagger: .1, ease: 'power3.out'
    });
  });

  gsap.from('.feature-card', {
    scrollTrigger: { trigger: '.bento', start: 'top 78%' },
    y: 70, scale: .92, opacity: 0, duration: 1, stagger: .12, ease: 'power3.out'
  });

  gsap.fromTo('.demo-media',
    { scale: .82, opacity: .35 },
    { scale: 1, opacity: 1, ease: 'none', scrollTrigger: { trigger: '.demo-section', start: 'top 85%', end: 'bottom 65%', scrub: 1.2 } }
  );

  gsap.from('.scrub-copy', {
    scrollTrigger: { trigger: '.demo-copy', start: 'top 72%', end: 'bottom 45%', scrub: 1 },
    opacity: .12, y: 30
  });

  gsap.to('.story-visual img', {
    yPercent: -8, ease: 'none', scrollTrigger: { trigger: '.story-section', start: 'top bottom', end: 'bottom top', scrub: 1.3 }
  });

  document.querySelectorAll('.count-up').forEach((counter) => {
    const state = { value: 0 };
    gsap.to(state, {
      value: Number(counter.dataset.count), duration: 1.8, ease: 'power2.out',
      scrollTrigger: { trigger: counter, start: 'top 88%', once: true },
      onUpdate: () => { counter.textContent = Math.round(state.value); }
    });
  });
}
