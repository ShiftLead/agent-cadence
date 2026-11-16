#!/usr/bin/env python3
# SYNCED FILE — canonical copy: ShiftLead/agent-cadence files/scripts/person_text.py
# Edit it there: a repo runs it from its pinned agent-cadence (`agent-cadence path`), and a fix reaches it by a bump PR.
"""Text a person reads, checked at its writer (TD-268; ShiftLead design §4.10 *Text a person reads is checked at
its writer*; ledgerboard's TD-111 plan, D1, D2, D4).

The rules are ledgerboard's (``person_text_problems``, ``title_problems``, ``sentence_problems``); the words are
the process's, ``person_text.json`` beside this file — the role nouns a consequence may name as who acts
(``actors``), and the coined words and label patterns a title may not hold (``coined``, ``labels``). Rules 1–3
refuse a write and list every problem at once; rule 4 warns. This repo's command-line writers call it
(``ledger.py``: a title, an Ask, an Answers; ``board_edit.py add``: a ``decide`` or ``act`` line); ledgerboard's
own writers never do (the plan's D3).
"""
from __future__ import annotations

import json
import re
import sys
from collections.abc import Sequence
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ledgerboard as LB  # noqa: E402  # sibling SYNC package (the vendored tag is tests/ledgerboard.MANIFEST's)

VOCABULARY = Path(__file__).with_name("person_text.json")
PARA_RE = re.compile(r"\n[ \t]*\n")


def vocabulary(path: Path = VOCABULARY) -> dict[str, list[str]]:
    """``person_text.json``'s three lists: ``actors``, ``coined``, ``labels``."""
    data = json.loads(path.read_text(encoding="utf-8"))
    return {k: list(data.get(k) or []) for k in ("actors", "coined", "labels")}


def ask_problems(text: str, people: Sequence[str] = ()) -> list[LB.PersonTextProblem]:
    """An entry's Ask (cadence.md §2.3): its first paragraph one plain question of one sentence (rule 1), its later
    paragraphs the context (rule 4, a warning)."""
    parts = PARA_RE.split(text.strip(), maxsplit=1)
    first, rest = parts[0], (parts[1].strip() if len(parts) > 1 else "")
    return LB.person_text_problems(first, (), rest or None, question=True, people=people,
                                   actors=vocabulary()["actors"])


def answers_problems(text: str, people: Sequence[str] = ()) -> list[LB.PersonTextProblem]:
    """An entry's Answers (``a | b``, cadence.md §3.5): each answer says who acts in its consequence (rule 2)."""
    return LB.person_text_problems(None, LB.parse_answers_value(" ".join(text.split())), question=True,
                                   people=people, actors=vocabulary()["actors"])


def title_problems(title: str) -> list[LB.PersonTextProblem]:
    """An entry's title (rule 3): plain words, no code, id or label."""
    v = vocabulary()
    return LB.title_problems(title, coined=v["coined"], labels=v["labels"])


def report(prog: str, what: str, problems: Sequence[LB.PersonTextProblem]) -> bool:
    """Print each problem to stderr under ``prog``; True when one refuses the write."""
    for p in problems:
        print(f"{prog}: {'refused' if p.refuse else 'warning'} — {what}: {p.line}", file=sys.stderr)
    return any(p.refuse for p in problems)
