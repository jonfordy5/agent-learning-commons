/* Public-site utility. No analytics or external requests.
 * Auto-discovers the GitHub owner/repository for project Pages sites:
 *   https://OWNER.github.io/REPOSITORY/
 * To use a custom domain, fill in the repoOverride line below.
 */
(function () {
  'use strict';
  const repoOverride = ''; // e.g. 'https://github.com/your-name/agent-learning-commons'
  function sourceRepo() {
    if (repoOverride) return repoOverride.replace(/\/$/, '');
    const host = window.location.hostname;
    const match = host.match(/^([a-zA-Z0-9-]+)\.github\.io$/i);
    const segment = window.location.pathname.split('/').filter(Boolean)[0];
    if (!match || !segment || !/^[\w.-]+$/.test(segment)) return null;
    return `https://github.com/${match[1]}/${segment}`;
  }
  const repo = sourceRepo();
  document.querySelectorAll('[data-github]').forEach(function (el) {
    if (!repo) { el.hidden = true; return; }
    const destinations = {
      repo: repo,
      join: `${repo}/issues/new?template=join.yml`,
      lesson: `${repo}/issues/new?template=lesson.yml`,
      issues: `${repo}/issues`
    };
    const href = destinations[el.dataset.github];
    if (href) { el.href = href; el.hidden = false; }
    else el.hidden = true;
  });
})();
