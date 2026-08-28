const section = document.querySelector('[data-pressure]');
const slider = document.querySelector('#storage');
const nav = document.querySelector('[data-nav]');
const pageProgress = document.querySelector('[data-page-progress]');

const states = {
  normal: ['NORMAL', 'Keep watching.', 'Storage is below the warning threshold. No action is taken.'],
  warning: ['90% WARNING', 'You get a clear alert.', 'The menu-bar icon changes and macOS sends one notification.'],
  critical: ['95% CLEANUP', 'Safe cleanup can begin.', 'If enabled, the allow-listed cleaner runs with a six-hour cooldown.']
};

function updatePressure() {
  const value = Number(slider.value);
  const level = value >= 95 ? 'critical' : value >= 90 ? 'warning' : 'normal';
  const color = level === 'critical' ? '#ff6c56' : level === 'warning' ? '#f28c38' : '#6f9a76';
  section.dataset.level = level;
  section.style.setProperty('--percent', value);
  section.style.setProperty('--gauge-color', color);
  document.querySelector('[data-percent]').textContent = `${value}%`;
  document.querySelector('[data-state]').textContent = states[level][0];
  document.querySelector('[data-title]').textContent = states[level][1];
  document.querySelector('[data-copy]').textContent = states[level][2];
}

slider.addEventListener('input', updatePressure);
updatePressure();

function updateChrome() {
  const scrollable = document.documentElement.scrollHeight - window.innerHeight;
  const progress = scrollable > 0 ? window.scrollY / scrollable : 0;
  pageProgress.style.transform = `scaleX(${Math.min(Math.max(progress, 0), 1)})`;
  nav.classList.toggle('is-scrolled', window.scrollY > 24);
}

window.addEventListener('scroll', updateChrome, { passive: true });
updateChrome();
