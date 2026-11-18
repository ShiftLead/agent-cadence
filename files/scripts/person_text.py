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


def ask_problems(text: str, people: Sequence[str] = (), context: str | None = None) -> list[LB.PersonTextProblem]:
    """An entry's Ask (cadence.md §2.3): its first paragraph one plain question of one sentence (rule 1), its later
    paragraphs — and ``context``, the ``**Context:**`` section written beside it (ledgerboard v3.3, TD-284) — the
    context (rule 4, a warning)."""
    parts = PARA_RE.split(text.strip(), maxsplit=1)
    first, rest = parts[0], (parts[1].strip() if len(parts) > 1 else "")
    rest = "\n\n".join(x for x in (rest, (context or "").strip()) if x)
    return LB.person_text_problems(first, (), rest or None, question=True, people=people,
                                   actors=vocabulary()["actors"])


def context_problems(text: str, people: Sequence[str] = ()) -> list[LB.PersonTextProblem]:
    """An Ask's ``**Context:**`` section written alone (TD-284): rule 4, a warning, on its code tokens."""
    return LB.person_text_problems(None, (), text.strip() or None, question=True, people=people,
                                   actors=vocabulary()["actors"])


def answers_problems(text: str, people: Sequence[str] = ()) -> list[LB.PersonTextProblem]:
    """An entry's Answers (``a | b``, cadence.md §3.5): each answer says who acts in its consequence (rule 2)."""
    return LB.person_text_problems(None, LB.parse_answers_value(" ".join(text.split())), question=True,
                                   people=people, actors=vocabulary()["actors"])


BOLD_OPEN_RE = re.compile(r"\*\*(?P<head>.+?)\*\*(?P<tail>.*)", re.S)
DETAIL_CONTEXT = ("context", "caveats", "recommended", "otherwise")  # rule 4's parts of a detail block


def board_problems(kind: str, text: str, answers: Sequence[str] = (), detail: dict | None = None,
                   people: Sequence[str] = ()) -> list[LB.PersonTextProblem]:
    """A board line ``board_edit.py add`` writes (cadence.md §3.3, §3.5): a ``decide``'s bold opening, when it has
    one, is its whole question (rule 1; with none the text is read whole), a bold run past it is refused, each
    ``--answer`` says who acts (rule 2); an ``act`` opens with its task in bold (rule 1, a statement). The tail and
    the detail block's context, caveats, recommended and otherwise are rule 4, a warning. The line's ``Context:``
    field names a gate and is never read. Other kinds are not checked."""
    if kind not in ("decide", "act"):
        return []
    actors = vocabulary()["actors"]
    text = (text or "").strip()
    m = BOLD_OPEN_RE.match(text)
    out: list[LB.PersonTextProblem] = []
    if kind == "act" and m is None:
        out.append(LB.PersonTextProblem(1, True, "an act opens with its task in bold: **<the task>** then the rest"))
    if kind == "decide" and m is not None and "**" in m.group("tail"):
        out.append(LB.PersonTextProblem(1, True, "a decide's text holds one bold run, its opening question; "
                                                 "a bold run later in the text is refused"))
    if kind == "decide" and m is None and "**" in text:
        out.append(LB.PersonTextProblem(1, True, "a decide's bold run opens the text and is its whole question; "
                                                 "a bold run mid-text is refused"))
    sentence = m.group("head").strip() if m else (text if kind == "decide" else None)
    tail = m.group("tail").strip(" \t\n—-–") if m else ""
    context = "\n".join([tail] + [str((detail or {}).get(k) or "") for k in DETAIL_CONTEXT]).strip() or None
    out += LB.person_text_problems(sentence, list(answers) if kind == "decide" else (), context,
                                   question=kind == "decide", people=people, actors=actors)
    return sorted(out, key=lambda p: p.rule)


def title_problems(title: str) -> list[LB.PersonTextProblem]:
    """An entry's title (rule 3): plain words, no code, id or label."""
    v = vocabulary()
    return LB.title_problems(title, coined=v["coined"], labels=v["labels"])


def report(prog: str, what: str, problems: Sequence[LB.PersonTextProblem]) -> bool:
    """Print each problem to stderr under ``prog``; True when one refuses the write."""
    for p in problems:
        print(f"{prog}: {'refused' if p.refuse else 'warning'} — {what}: {p.line}", file=sys.stderr)
    return any(p.refuse for p in problems)
