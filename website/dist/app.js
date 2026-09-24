(() => {
  const toggle = document.getElementById('shelf-toggle');
  const control = document.getElementById('demo-control');
  const label = document.getElementById('demo-control-label');
  const shelf = document.getElementById('demo-shelf');
  const desktop = document.querySelector('.desktop');
  const change = () => {
    const expanded = toggle.getAttribute('aria-expanded') !== 'true';
    toggle.setAttribute('aria-expanded', String(expanded));
    toggle.setAttribute('aria-label', expanded ? '收起收纳栏' : '展开收纳栏');
    shelf.hidden = !expanded;
    desktop.classList.toggle('collapsed', !expanded);
    label.textContent = expanded ? '试试收起' : '试试展开';
  };
  toggle.addEventListener('click', change);
  control.addEventListener('click', change);
})();
