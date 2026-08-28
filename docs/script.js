export function pressureLevel(value) {
  return value >= 78 ? 'critical' : value >= 75 ? 'warning' : 'normal';
}

export function cleanupValue(start, progress, target = 72) {
  const safeProgress = Math.min(Math.max(progress, 0), 1);
  const eased = 1 - ((1 - safeProgress) ** 3);
  return Math.round((start + ((target - start) * eased)) * 10) / 10;
}

export function rangePosition(value, min = 70, max = 99) {
  return Math.min(Math.max(((value - min) / (max - min)) * 100, 0), 100);
}

const section = typeof document === 'undefined' ? null : document.querySelector('[data-pressure]');

if (section) {
  const slider = section.querySelector('#storage');
  const autoClean = section.querySelector('[data-auto-clean]');
  const timeline = [...section.querySelectorAll('.cleanup-timeline li')];
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const states = {
    normal: ['NORMAL', 'Keep watching.', 'Storage is below the warning threshold. No action is taken.', 'Storage pressure is normal.'],
    warning: ['75% ALERT', 'Pressure is rising.', 'The menu-bar icon changes and macOS sends one notification.', 'Storage pressure needs attention.'],
    critical: ['78% CLEANUP', 'Pressure critical.', 'Automatic safe cleanup will begin using the strict allow list.', 'Cleanup threshold reached.'],
    cleaning: ['SAFE CLEANUP', 'Pressure is falling.', 'Only allow-listed caches and generated build files are being removed.', 'Safe cleanup is running.'],
    optimized: ['OPTIMIZED', 'Pressure relieved.', 'The browser simulation reached the healthy target without touching personal files.', 'Storage pressure is healthy.']
  };
  let cleanupTimer;
  let cleanupFrame;
  let phase = 'idle';

  function setTimeline(activeStep = -1, complete = false) {
    timeline.forEach((item, index) => {
      item.classList.toggle('is-done', complete || index < activeStep);
      item.classList.toggle('is-active', !complete && index === activeStep);
    });
  }

  function render(value, progress = 0) {
    const level = pressureLevel(value);
    const state = phase === 'cleaning' ? states.cleaning : phase === 'optimized' ? states.optimized : states[level];
    const color = level === 'critical' ? '#ce4333' : level === 'warning' ? '#d97724' : '#6f9a76';
    section.dataset.level = level;
    section.dataset.phase = phase;
    section.style.setProperty('--percent', value);
    section.style.setProperty('--gauge-color', color);
    section.style.setProperty('--range-position', `${rangePosition(value)}%`);
    section.querySelector('[data-percent]').textContent = `${Math.round(value)}%`;
    section.querySelector('[data-state]').textContent = state[0];
    section.querySelector('[data-title]').textContent = state[1];
    section.querySelector('[data-copy]').textContent = state[2];
    section.querySelector('[data-gauge-status]').textContent = state[3];

    if (phase === 'cleaning') setTimeline(progress < 0.3 ? 1 : progress < 0.88 ? 2 : 3);
    else if (phase === 'optimized') setTimeline(3, true);
    else setTimeline(level === 'critical' ? 0 : -1);
  }

  function stopCleanup() {
    window.clearTimeout(cleanupTimer);
    window.cancelAnimationFrame(cleanupFrame);
  }

  function startCleanup() {
    const start = Number(slider.value);
    if (start < 78 || autoClean.getAttribute('aria-pressed') !== 'true') return;
    phase = 'cleaning';

    if (reducedMotion.matches) {
      slider.value = '72';
      phase = 'optimized';
      render(72, 1);
      return;
    }

    const startedAt = performance.now();
    const duration = 3200;
    const tick = now => {
      const progress = Math.min((now - startedAt) / duration, 1);
      const value = cleanupValue(start, progress);
      slider.value = String(value);
      render(value, progress);
      if (progress < 1) cleanupFrame = window.requestAnimationFrame(tick);
      else {
        phase = 'optimized';
        render(72, 1);
      }
    };
    cleanupFrame = window.requestAnimationFrame(tick);
  }

  function scheduleCleanup() {
    stopCleanup();
    if (Number(slider.value) >= 78 && autoClean.getAttribute('aria-pressed') === 'true') cleanupTimer = window.setTimeout(startCleanup, 800);
  }

  slider.addEventListener('input', () => {
    stopCleanup();
    phase = 'idle';
    render(Number(slider.value));
    scheduleCleanup();
  });

  autoClean.addEventListener('click', () => {
    const enabled = autoClean.getAttribute('aria-pressed') !== 'true';
    autoClean.setAttribute('aria-pressed', String(enabled));
    autoClean.querySelector('[data-auto-label]').textContent = enabled ? 'On' : 'Off';
    if (enabled) scheduleCleanup();
    else stopCleanup();
  });

  render(Number(slider.value));
}

if (typeof window !== 'undefined') {
  const nav = document.querySelector('[data-nav]');
  const pageProgress = document.querySelector('[data-page-progress]');
  const updateChrome = () => {
    const scrollable = document.documentElement.scrollHeight - window.innerHeight;
    const progress = scrollable > 0 ? window.scrollY / scrollable : 0;
    pageProgress.style.transform = `scaleX(${Math.min(Math.max(progress, 0), 1)})`;
    nav.classList.toggle('is-scrolled', window.scrollY > 24);
  };
  window.addEventListener('scroll', updateChrome, { passive: true });
  updateChrome();

  const leadForm = document.querySelector('[data-lead-form]');
  if (leadForm) {
    const formWrap = document.querySelector('[data-lead-form-wrap]');
    const ready = document.querySelector('[data-download-ready]');
    const downloadLink = document.querySelector('[data-download-link]');
    const status = leadForm.querySelector('[data-form-status]');
    const submit = leadForm.querySelector('button[type="submit"]');

    leadForm.addEventListener('submit', async event => {
      event.preventDefault();
      if (!leadForm.reportValidity() || submit.disabled) return;
      submit.disabled = true;
      status.textContent = 'Registering your download…';
      status.dataset.kind = 'pending';

      try {
        const fields = new FormData(leadForm);
        const response = await fetch('https://cfgauss.com.br/api/lead/clean-my-mac', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(Object.fromEntries(fields))
        });
        const result = await response.json();
        if (!response.ok || !result.success || !result.downloadUrl) throw new Error(result.error || 'Download could not be unlocked.');
        downloadLink.href = result.downloadUrl;
        formWrap.hidden = true;
        ready.hidden = false;
        ready.focus();
      } catch (error) {
        status.textContent = error.message || 'Download could not be unlocked. Try again.';
        status.dataset.kind = 'error';
        submit.disabled = false;
      }
    });
  }
}
