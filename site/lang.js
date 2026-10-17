// Shows the page in Russian or English: ?lang=, then the saved choice, then the browser language.
(function () {
  var root = document.documentElement;
  root.classList.add('js');

  function saved() {
    try { return localStorage.getItem('lang'); } catch (e) { return null; }
  }

  function pick() {
    var query = new URLSearchParams(location.search).get('lang');
    if (query === 'ru' || query === 'en') return query;
    var stored = saved();
    if (stored === 'ru' || stored === 'en') return stored;
    var langs = navigator.languages || [navigator.language || 'en'];
    for (var i = 0; i < langs.length; i++) {
      var code = String(langs[i]).toLowerCase().slice(0, 2);
      if (code === 'ru' || code === 'en') return code;
    }
    return 'en';
  }

  function apply(lang) {
    root.lang = lang;
    document.querySelectorAll('[data-lang]').forEach(function (el) {
      el.classList.toggle('shown', el.dataset.lang === lang);
    });
    document.querySelectorAll('nav.lang button').forEach(function (b) {
      b.setAttribute('aria-pressed', String(b.dataset.set === lang));
    });
    var title = document.querySelector('meta[name="title-' + lang + '"]');
    if (title) document.title = title.content;
  }

  document.addEventListener('DOMContentLoaded', function () {
    apply(pick());
    document.querySelectorAll('nav.lang button').forEach(function (b) {
      b.addEventListener('click', function () {
        try { localStorage.setItem('lang', b.dataset.set); } catch (e) {}
        apply(b.dataset.set);
      });
    });
  });
})();
