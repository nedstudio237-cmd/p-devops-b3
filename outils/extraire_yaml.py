#!/usr/bin/env python3
"""Extrait les manifestes d'un énoncé de TP Markdown.

Un bloc ```yaml précédé (ligne non vide juste au-dessus) d'une ligne `nom-fichier.yaml`
est écrit dans ce fichier. Les espaces/tabulations d'indentation de liste sont retirés.
Usage : extraire_yaml.py <TP.md> <dossier_sortie> [ancien=nouveau ...]
"""
import re
import sys
from pathlib import Path

src, out, *subs = sys.argv[1:]
out = Path(out)
lines = Path(src).read_text(encoding="utf-8").splitlines()
pending = None
i = 0
while i < len(lines):
    line = lines[i]
    m = re.fullmatch(r"\s*`([\w./-]+\.ya?ml)`\s*", line)
    if m:
        pending = m.group(1)
    elif re.fullmatch(r"\s*```ya?ml\s*", line) and pending:
        indent = re.match(r"\s*", line).group(0)
        body = []
        i += 1
        while not re.fullmatch(r"\s*```\s*", lines[i]):
            body.append(lines[i][len(indent):] if lines[i].startswith(indent) else lines[i])
            i += 1
        text = "\n".join(body) + "\n"
        for s in subs:
            old, new = s.split("=", 1)
            text = text.replace(old, new)
        (out / pending).write_text(text, encoding="utf-8")
        print("écrit :", pending)
        pending = None
    elif line.strip() and not line.strip().startswith("```"):
        if not m:
            pending = pending if line.strip().startswith("`") else None
    i += 1
