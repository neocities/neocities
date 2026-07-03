(function() {
  var themeKey = 'neocities-theme';
  var darkClass = 'dark-Mode';

  function hasDarkClass() {
    if (document.documentElement.classList) {
      return document.documentElement.classList.contains(darkClass);
    }

    return new RegExp('(^| )' + darkClass + '( |$)').test(document.documentElement.className);
  }

  function storedTheme() {
    try {
      return localStorage.getItem(themeKey);
    } catch (e) {
      return null;
    }
  }

  function prefersDarkMode() {
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
  }

  function initialThemeIsDark() {
    var savedTheme = storedTheme();

    if (savedTheme === 'dark') {
      return true;
    }

    if (savedTheme === 'light') {
      return false;
    }

    storeTheme(false);
    return false;
  }

  function setTheme(isDark) {
    if (document.documentElement.classList) {
      document.documentElement.classList.toggle(darkClass, isDark);
    } else {
      document.documentElement.className = document.documentElement.className.replace(new RegExp('(^| )' + darkClass + '( |$)'), ' ');
      if (isDark) {
        document.documentElement.className += ' ' + darkClass;
      }
    }

    document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light');

    var toggles = document.querySelectorAll('[data-theme-toggle]');
    for (var i = 0; i < toggles.length; i++) {
      var icon = toggles[i].querySelector('.fa');
      var label = toggles[i].querySelector('.theme-ToggleText');
      var text = isDark ? 'Light Mode' : 'Dark Mode';

      toggles[i].setAttribute('aria-pressed', isDark ? 'true' : 'false');
      toggles[i].setAttribute('aria-label', isDark ? 'Switch to light mode' : 'Switch to dark mode');
      toggles[i].setAttribute('title', isDark ? 'Switch to light mode' : 'Switch to dark mode');

      if (icon) {
        icon.className = 'fa ' + (isDark ? 'fa-sun-o' : 'fa-moon-o');
      }

      if (label) {
        label.textContent = text;
      }
    }
  }

  function storeTheme(isDark) {
    try {
      localStorage.setItem(themeKey, isDark ? 'dark' : 'light');
    } catch (e) {}
  }

  document.addEventListener('DOMContentLoaded', function() {
    setTheme(initialThemeIsDark());

    var toggles = document.querySelectorAll('[data-theme-toggle]');
    for (var i = 0; i < toggles.length; i++) {
      toggles[i].onclick = function(event) {
        event.preventDefault();

        var isDark = !hasDarkClass();
        storeTheme(isDark);
        setTheme(isDark);
      };
    }
  });
})();
