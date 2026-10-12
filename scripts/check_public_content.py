#!/usr/bin/env python3
"""Fail closed on unreviewed tracked paths and credential-shaped content.

This automated check supplements human source review. It cannot prove that
arbitrary prose, names or encoded binaries contain no personal information.
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
if not (root / '.git').is_dir():
    raise SystemExit('Run this check inside the independent public Git repository.')

files = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
root_files = {'README.md', 'LICENSE', '.gitignore', '.env.example'}
prefixes = ('site/', 'integrations/supabase/call-report-mcp/',
            'supabase/migrations/', 'supabase/tests/database/',
            'docs/public-distribution/', 'scripts/')
allowed_suffixes = {'.md', '.sql', '.py', '.mjs', '.ts', '.tsx', '.css', '.json', '.svg'}
blocked_parts = {'.openai', '.wrangler', '.env.local', 'node_modules', 'dist', '.next',
                 '.vinext', 'exports', 'backups', 'reports', 'operations', 'inputs',
                 'work', 'tmp', 'data', 'outputs', '.codex', '.agents'}
patterns = {
    'private_key': r'-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----',
    'provider_token': r'\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-(?:proj-)?[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{30,}|(?:AKIA|ASIA)[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{10,})\b',
    'jwt': r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b',
    'supabase_key': r'\bsb_(?:secret|publishable)_[A-Za-z0-9_-]{15,}',
    'credential_url': r'(?i)\b(?:https?|postgres(?:ql)?)://[^\s/:@]+:[^\s/@]+@',
    'user_path': r'/Us' + r'ers/[^/\s"<>]+/|C:\\Us' + r'ers\\[^\\\s]+\\',
    'hosted_instance': r'https://[a-z0-9-]+\.(?:supabase\.co|chatgpt\.site)',
    'deployment_id': r'\bappg(?:prj|dep)_[a-zA-Z0-9]+',
}
email = re.compile(r'(?i)(?<![\w.%+-])([\w.%+-]+)@([a-z0-9.-]+\.[a-z]{2,})')
failures = []
checked = 0
for relative in filter(None, files):
    path = root / relative
    if path.is_symlink():
        failures.append((relative, 'symlink')); continue
    if any(p in blocked_parts for p in Path(relative).parts):
        failures.append((relative, 'excluded_path')); continue
    if relative not in root_files and (not relative.startswith(prefixes)
        or (path.suffix not in allowed_suffixes and path.name not in {'.gitignore', '.env.example'})):
        failures.append((relative, 'not_allowlisted')); continue
    try:
        content = path.read_text(encoding='utf-8')
    except (UnicodeError, OSError):
        failures.append((relative, 'unreviewed_binary_or_missing')); continue
    checked += 1
    for label, pattern in patterns.items():
        if re.search(pattern, content): failures.append((relative, label))
    for match in email.finditer(content):
        domain = match.group(2).lower()
        if not (domain in {'example.com', 'example.org', 'example.net'}
                or domain.endswith(('.invalid', '.example', '.test'))):
            failures.append((relative, 'non_synthetic_email'))
for relative, label in sorted(set(failures)):
    print(f'FAIL {relative}: {label}')
print(f'Tracked text files checked: {checked}; findings: {len(set(failures))}')
sys.exit(bool(failures))
