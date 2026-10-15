#!/usr/bin/env python3
"""Add one opt-in experimental WebMCP script tag to the existing workspace.
Does not change its existing JS, Supabase settings, accounts, or UI controls.
"""
from pathlib import Path

p = Path('research-workspace.html')
if not p.exists():
    raise SystemExit('ERROR: Run from the repository root, containing research-workspace.html')
s = p.read_text(encoding='utf-8')
tag = '<script defer src="./commons-site-tools.js"></script>'
if tag in s:
    print('UNCHANGED: read-only site tools are already linked.')
    raise SystemExit(0)
if not Path('commons-site-tools.js').exists():
    raise SystemExit('ERROR: Upload commons-site-tools.js to this directory first')
needle = '</script></body></html>'
if s.count(needle) != 1:
    raise SystemExit('ERROR: Unexpected workspace layout. No changes made. Ask for review.')
p.write_text(s.replace(needle, '</script>' + tag + '</body></html>'), encoding='utf-8')
print('SUCCESS: Added read-only site tool script to research-workspace.html')
print('NEXT: Review git diff, then commit and publish when ready.')
