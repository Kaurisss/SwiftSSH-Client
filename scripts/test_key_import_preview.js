// Browser-console self-check, also runnable via Chrome DevTools evaluate_script.
() => {
  const results = [];
  const check = (condition, message) => {
    if (!condition) throw new Error(message);
    results.push(message);
  };
  const layout = name => {
    const width = document.documentElement.clientWidth;
    const overflow = [...document.querySelectorAll('button,input,textarea,select')].filter(element => {
      if (!element.getClientRects().length) return false;
      const rect = element.getBoundingClientRect();
      return rect.left < -1 || rect.right > width + 1;
    });
    check(document.documentElement.scrollWidth <= width && !overflow.length, name + ' fits the viewport');
  };
  const click = selector => {
    const element = document.querySelector(selector);
    if (!element) throw new Error('Missing control: ' + selector);
    element.click();
  };
  const input = (selector, value) => {
    const element = document.querySelector(selector);
    element.value = value;
    element.dispatchEvent(new Event('input', { bubbles: true }));
  };
  const reset = () => {
    click('#cancel');
    click('[data-action="reset"]');
  };
  reset();
  check(!document.querySelector('#key-name'), 'Inputs are hidden until a source is chosen');
  layout('Initial source choices');
  check(document.querySelectorAll('[data-source]').length === 2, 'Both source choices are available');
  click('#help-button');
  check(!!document.querySelector('#import-help'), 'Help expands');
  click('#help-button');
  check(!document.querySelector('#import-help'), 'Help collapses');

  click('[data-source="file"]');
  check(!!document.querySelector('#key-name') && !document.querySelector('#private-key'), 'File source shows preview and naming, not the editor');
  layout('File preview');
  click('summary');
  check(document.querySelector('details').open && document.querySelector('details code').textContent.startsWith('SHA256:'), 'Full fingerprint is reachable');
  input('#key-name', '');
  document.querySelector('form').requestSubmit();
  check(document.querySelector('#key-name').getAttribute('aria-invalid') === 'true', 'Empty name has an inline recovery message');
  const name = '<img src=x>运维密钥';
  input('#key-name', name);
  document.querySelector('form').requestSubmit();
  check(document.querySelector('#screen-title').textContent === '导入预览完成', 'File path reaches simulated import success');
  click('[data-action="manager"]');
  check(document.querySelector('.manager-keys strong').textContent === name && !document.querySelector('.manager-keys img'), 'User-provided labels are escaped');
  layout('Key list');

  reset();
  click('[data-source="paste"]');
  check(!!document.querySelector('#private-key'), 'Paste source exposes the editor');
  layout('Paste editor');
  input('#private-key', 'not-a-key');
  document.querySelector('form').requestSubmit();
  check(document.querySelector('#private-key').getAttribute('aria-invalid') === 'true', 'Non-demo material is rejected with a recovery instruction');
  check(document.activeElement.id === 'private-key', 'Validation focuses the failing field');
  click('[data-source="paste"]');
  input('#key-name', '家用 NAS · 示例');
  document.querySelector('form').requestSubmit();
  check(document.querySelector('#screen-title').textContent === '导入预览完成', 'Paste path reaches simulated import success');
  reset();

  for (const theme of ['light', 'dark']) {
    const select = document.querySelector('#theme');
    select.value = theme;
    select.dispatchEvent(new Event('change', { bubbles: true }));
    check(document.querySelector('#phone').dataset.theme === theme, theme + ' appearance switches');
  }
  document.querySelector('#theme').value = 'light';
  document.querySelector('#theme').dispatchEvent(new Event('change'));
  check(document.documentElement.scrollWidth <= document.documentElement.clientWidth, 'No horizontal page overflow');
  check(!document.querySelector('[data-variant], .variant-picker'), 'No variant picker remains');
  window.scrollTo(0, 0);
  return { passed: results.length, checks: results, viewport: [innerWidth, innerHeight] };
}
