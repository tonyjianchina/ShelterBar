(() => {
  const desktop = document.querySelector('.desktop');
  if (!desktop) return;

  const glyphs = [...desktop.querySelectorAll('.demo-glyph')];
  const sources = [...desktop.querySelectorAll('.menu-slot')];
  const targets = [...desktop.querySelectorAll('.demo-app')];
  const shelf = desktop.querySelector('.demo-shelf');
  const toggle = desktop.querySelector('.shelf-toggle');
  const cursor = desktop.querySelector('.demo-cursor');
  const count = desktop.querySelector('.count');
  const status = desktop.querySelector('.demo-status');
  const pause = document.querySelector('.demo-pause');
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const duration = 11600;
  const dragStarts = [2750, 4450, 6150];
  let geometry;
  let elapsed = 0;
  let previousTime = null;
  let frame = null;
  let inView = true;
  let paused = false;

  const clamp = value => Math.max(0, Math.min(1, value));
  const ease = value => {
    const t = clamp(value);
    return t * t * (3 - 2 * t);
  };
  const between = (from, to, progress) => ({
    x: from.x + (to.x - from.x) * progress,
    y: from.y + (to.y - from.y) * progress,
  });
  const moveGlyph = (glyph, point, scale = 1) => {
    glyph.style.transform = `translate(${point.x - 10}px, ${point.y - 10}px) scale(${scale})`;
  };

  function measure() {
    // Measure the shelf without its entrance transform so targets stay stable.
    const rect = desktop.getBoundingClientRect();
    const center = element => {
      const box = element.getBoundingClientRect();
      return { x: box.left - rect.left - desktop.clientLeft + box.width / 2,
        y: box.top - rect.top - desktop.clientTop + box.height / 2 };
    };
    shelf.style.transform = 'none';
    geometry = { from: sources.map(center), to: targets.map(center), toggle: center(toggle),
      home: { x: desktop.clientWidth * .72, y: 165 } };
    render(reducedMotion.matches ? 9000 : elapsed);
  }

  function render(time) {
    if (!geometry) return;
    const still = reducedMotion.matches;
    const fade = still ? 1 : Math.min(clamp(time / 450), 1 - clamp((time - 11000) / 600));
    const open = still ? 1 : ease((time - 2080) / 450);
    shelf.style.opacity = String(open * fade);
    shelf.style.transform = `translateY(${(1 - open) * -10}px) scale(${.98 + open * .02})`;
    toggle.classList.toggle('is-open', open > .5);
    toggle.classList.toggle('is-pressed', time >= 1900 && time < 2180 && !still);

    let collected = 0;
    let pointer = between(geometry.home, geometry.toggle, ease((time - 1200) / 700));
    let dragging = false;
    glyphs.forEach((glyph, index) => {
      const start = dragStarts[index];
      const pickup = start + 600;
      const drop = pickup + 1050;
      const progress = ease((time - pickup) / 1050);
      const point = between(geometry.from[index], geometry.to[index], progress);
      // A gentle arc makes the motion read as a hand-guided drag.
      point.x += Math.sin(progress * Math.PI) * 10;
      const held = time >= pickup && time < drop;
      moveGlyph(glyph, point, held ? 1 + Math.sin(progress * Math.PI) * .12 : 1);
      glyph.style.opacity = String(fade);
      targets[index].classList.toggle('is-target', held && !still);
      if (time >= drop) collected++;

      if (time >= start && time < drop) {
        const previous = index === 0 ? geometry.toggle : {
          x: geometry.to[index - 1].x + 5, y: geometry.to[index - 1].y + 7,
        };
        pointer = time < pickup
          ? between(previous, { x: geometry.from[index].x + 5, y: geometry.from[index].y + 7 }, ease((time - start) / 500))
          : { x: point.x + 5, y: point.y + 7 };
        dragging = held;
      } else if (time >= drop && (index === 2 || time < dragStarts[index + 1])) {
        pointer = { x: geometry.to[index].x + 5, y: geometry.to[index].y + 7 };
      }
    });

    if (time >= 7950) {
      pointer = between({ x: geometry.to[2].x + 5, y: geometry.to[2].y + 7 }, geometry.home, ease((time - 7950) / 650));
    }
    cursor.style.transform = `translate(${pointer.x}px, ${pointer.y}px)`;
    cursor.style.opacity = String(still ? 0 : clamp((time - 1050) / 300) * (1 - clamp((time - 8200) / 400)) * fade);
    cursor.classList.toggle('is-pressed', dragging || (time >= 1900 && time < 2180 && !still));
    count.textContent = String(collected);
    const phase = time < 1900 ? 'ready' : time < 2750 ? 'opening' : collected < 3 ? 'dragging' : 'complete';
    desktop.dataset.demoPhase = phase;
    desktop.dataset.collected = String(collected);
    status.textContent = { ready: '顶部图标，一眼可见', opening: '展开收纳栏', dragging: '拖进去，收好', complete: '图标收好了，菜单栏清爽了' }[phase];
  }

  function tick(now) {
    if (previousTime !== null) elapsed = (elapsed + Math.min(now - previousTime, 100)) % duration;
    previousTime = now;
    render(elapsed);
    frame = requestAnimationFrame(tick);
  }

  function syncPlayback() {
    if (frame !== null) cancelAnimationFrame(frame);
    frame = null;
    previousTime = null;
    pause.hidden = reducedMotion.matches;
    pause.textContent = paused ? '继续' : '暂停';
    pause.setAttribute('aria-label', paused ? '继续演示动画' : '暂停演示动画');
    if (reducedMotion.matches) render(9000);
    else if (!paused && inView && !document.hidden) frame = requestAnimationFrame(tick);
  }

  desktop.classList.add('is-animated');
  measure();
  pause.addEventListener('click', () => { paused = !paused; syncPlayback(); });
  document.addEventListener('visibilitychange', syncPlayback);
  reducedMotion.addEventListener('change', () => { elapsed = 0; measure(); syncPlayback(); });
  new ResizeObserver(measure).observe(desktop);
  new IntersectionObserver(entries => {
    inView = entries[0].isIntersecting;
    syncPlayback();
  }, { threshold: 0 }).observe(desktop);
  syncPlayback();
})();
