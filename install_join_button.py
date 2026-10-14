"""Insert the Join Research navigation button on the existing stock page.

Run in the repository root: python3 install_join_button.py
Safe and idempotent: does not overwrite/replace index.html.
"""
from pathlib import Path

p = Path(__file__).resolve().parent / 'index.html'
if not p.exists():
    raise SystemExit('ERROR: index.html not found. Put this script in the repository root.')
html = p.read_text(encoding='utf-8')
if 'join-research.html?ticker=${encodeURIComponent(s.symbol)}' in html:
    print('Join Research button is already installed; no changes made.')
    raise SystemExit(0)
needle = '<div class="kpis" style="margin-top:0">'
if html.count(needle) != 1 or 'function stockPage(symbol)' not in html:
    raise SystemExit('ERROR: index.html layout has changed. No modifications made.')
button = '''<div class="section-actions" style="margin:18px 0 20px">
  <a class="btn btn-mint" href="join-research.html?ticker=${encodeURIComponent(s.symbol)}">＋ Join research with my AI ↗</a>
  <span class="tiny">Join this stock's human research team · AI connection is separate</span>
</div>
'''
html = html.replace(needle, button + needle, 1)
p.write_text(html, encoding='utf-8')
print('SUCCESS: Added Join Research button to each stock workspace in index.html.')
print('Next: make sure join-research.html is uploaded and SQL setup is applied.')
