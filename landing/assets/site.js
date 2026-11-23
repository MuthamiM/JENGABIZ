(() => {
  const cookieName = 'jengabiz_cookie_preferences';
  const cookieMaxAge = 60 * 60 * 24 * 180;
  const banner = document.querySelector('[data-cookie-banner]');
  const dialog = document.querySelector('[data-cookie-dialog]');
  const analyticsToggle = document.querySelector('[data-cookie-analytics]');
  const marketingToggle = document.querySelector('[data-cookie-marketing]');

  const readConsent = () => {
    const entry = document.cookie
      .split(';')
      .map((value) => value.trim())
      .find((value) => value.startsWith(`${cookieName}=`));
    if (!entry) return null;
    const parts = decodeURIComponent(entry.slice(cookieName.length + 1)).split('.');
    if (parts.length !== 3 || parts[0] !== 'v1') return null;
    return { analytics: parts[1] === '1', marketing: parts[2] === '1' };
  };

  const saveConsent = (analytics, marketing) => {
    const secure = window.location.protocol === 'https:' ? '; Secure' : '';
    const value = `v1.${analytics ? '1' : '0'}.${marketing ? '1' : '0'}`;
    document.cookie = `${cookieName}=${encodeURIComponent(value)}; Path=/; Max-Age=${cookieMaxAge}; SameSite=Lax${secure}`;
    if (banner) banner.hidden = true;
    if (dialog?.open) dialog.close();
  };

  const openPreferences = () => {
    if (!dialog) {
      if (banner) banner.hidden = false;
      return;
    }
    const saved = readConsent();
    if (analyticsToggle) analyticsToggle.checked = saved?.analytics ?? false;
    if (marketingToggle) marketingToggle.checked = saved?.marketing ?? false;
    if (!dialog.open) dialog.showModal();
  };

  if (banner && !readConsent()) banner.hidden = false;

  document.querySelectorAll('[data-cookie-accept]').forEach((button) => {
    button.addEventListener('click', () => saveConsent(true, true));
  });

  document.querySelectorAll('[data-cookie-reject]').forEach((button) => {
    button.addEventListener('click', () => saveConsent(false, false));
  });

  document.querySelectorAll('[data-cookie-save]').forEach((button) => {
    button.addEventListener('click', () =>
      saveConsent(
        analyticsToggle?.checked ?? false,
        marketingToggle?.checked ?? false,
      ),
    );
  });

  document.querySelectorAll('[data-cookie-open]').forEach((button) => {
    button.addEventListener('click', openPreferences);
  });

  document.querySelectorAll('[data-cookie-manage]').forEach((button) => {
    button.addEventListener('click', openPreferences);
  });

  const code = new URLSearchParams(window.location.search).get('ref') || '';
  const referralCode = document.getElementById('referral-code');
  const referralNote = document.getElementById('referral-note');
  if (referralCode && referralNote && /^[A-Z0-9-]{4,32}$/i.test(code)) {
    referralCode.textContent = code.toUpperCase();
    referralNote.hidden = false;
  }

  const latestVersionLabels = document.querySelectorAll('[data-latest-version]');
  const latestApkLinks = document.querySelectorAll('[data-latest-apk]');
  const latestChecksumLinks = document.querySelectorAll('[data-latest-checksum]');
  if (
    latestVersionLabels.length ||
    latestApkLinks.length ||
    latestChecksumLinks.length
  ) {
    fetch('/downloads/latest.json', { cache: 'no-store' })
      .then((response) => {
        if (!response.ok) throw new Error('Latest release details unavailable.');
        return response.json();
      })
      .then((release) => {
        if (typeof release.version_name === 'string') {
          const versionName = release.version_name.trim();
          const versionLabel = versionName.startsWith('v')
            ? versionName
            : `v${versionName}`;
          latestVersionLabels.forEach((label) => {
            label.textContent = versionLabel;
          });
        }
        const versionCode = Number(release.version_code);
        if (Number.isSafeInteger(versionCode) && versionCode > 0) {
          const cacheKey = encodeURIComponent(String(versionCode));
          latestApkLinks.forEach((link) => {
            link.href = `/downloads/latest/JengaBiz.apk?v=${cacheKey}`;
          });
          latestChecksumLinks.forEach((link) => {
            link.href = `/downloads/latest/JengaBiz.sha256?v=${cacheKey}`;
          });
        }
      })
      .catch(() => {
        latestVersionLabels.forEach((label) => {
          label.textContent = 'latest';
        });
      });
  }
})();
