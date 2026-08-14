#!/usr/bin/env python3
"""Convert English title text to a practical Chicago-style title case."""

from __future__ import annotations

import re
import sys


# Chicago style lowercases articles, coordinating conjunctions, and
# prepositions of four letters or fewer.  This list is intentionally
# conservative: words not in it are treated as major words.
LOWERCASE_WORDS = {
    "a",
    "an",
    "and",
    "as",
    "at",
    "but",
    "by",
    "down",
    "for",
    "from",
    "in",
    "into",
    "like",
    "near",
    "nor",
    "n",
    "of",
    "off",
    "on",
    "onto",
    "or",
    "out",
    "over",
    "per",
    "past",
    "the",
    "than",
    "to",
    "till",
    "unto",
    "up",
    "via",
    "with",
}

# Common initialisms that the referenced converter recognizes as acronyms.
# Existing all-caps words are preserved independently of this list.
COMMON_ACRONYMS = {
    "ai",
    "api",
    "ceo",
    "dna",
    "faq",
    "html",
    "ios",
    "ml",
    "phd",
    "qa",
    "rna",
    "usa",
    "uk",
    "url",
    "ux",
}

WORD_RE = re.compile(r"[A-Za-z]+(?:['’][A-Za-z]+)*(?:-[A-Za-z]+(?:['’][A-Za-z]+)*)*")
BOUNDARY_RE = re.compile(r"[:.!?。！？—–]")


def _capitalize_word(word: str, *, preserve_all_caps: bool = True) -> str:
    """Capitalize the alphabetic parts of a word, preserving apostrophes."""

    if preserve_all_caps and any(c.isalpha() for c in word) and word.upper() == word:
        return word

    pieces = re.split(r"(['’])", word)
    result: list[str] = []
    for piece in pieces:
        if piece in {"'", "’"}:
            result.append(piece)
        elif piece:
            result.append(piece[:1].upper() + piece[1:].lower())
    return "".join(result)


def _word_form(word: str, *, major: bool) -> str:
    """Return a Chicago-style form while retaining acronyms where possible."""

    if "-" in word:
        parts = re.split(r"(-)", word)
        converted: list[str] = []
        first = True
        for part in parts:
            if part == "-":
                converted.append(part)
                continue
            # Chicago keeps modifiers following a musical key symbol lowercased:
            # F-sharp, B-flat, etc.
            musical_modifier = (
                not first
                and len(converted) >= 2
                and re.fullmatch(r"[A-Ga-g]-", "".join(converted[-2:]))
                and part.lower() in {"sharp", "flat", "natural"}
            )
            converted.append(
                _word_form(part, major=major if first else part.lower() not in LOWERCASE_WORDS)
                if not musical_modifier
                else part.lower()
            )
            first = False
        return "".join(converted)

    lower = word.lower()
    if lower in COMMON_ACRONYMS:
        return lower.upper()
    if major:
        return _capitalize_word(word)
    return word.lower()


def _convert_line(line: str) -> str:
    matches = list(WORD_RE.finditer(line))
    if not matches:
        return line

    # A title may contain a subtitle.  The first and last word of each
    # colon/em-dash-delimited part are treated as title words.
    segment_starts: set[int] = {0}
    segment_ends: set[int] = {len(matches) - 1}
    for index, match in enumerate(matches[:-1]):
        between = line[match.end() : matches[index + 1].start()]
        if BOUNDARY_RE.search(between):
            segment_starts.add(index + 1)
            segment_ends.add(index)
    segment_ends.add(len(matches) - 1)

    replacements: list[tuple[int, int, str]] = []
    for index, match in enumerate(matches):
        word = match.group(0)
        lower = word.lower()
        major = (
            index in segment_starts
            or index in segment_ends
            or lower not in LOWERCASE_WORDS
        )
        replacements.append((match.start(), match.end(), _word_form(word, major=major)))

    # Apply right-to-left so offsets remain valid and punctuation/spacing is
    # copied exactly as entered.
    converted = line
    for start, end, replacement in reversed(replacements):
        converted = converted[:start] + replacement + converted[end:]
    return converted


def convert(text: str) -> str:
    """Convert each line independently, preserving line breaks and spacing."""

    return "\n".join(_convert_line(line) for line in text.split("\n"))


if __name__ == "__main__":
    sys.stdout.write(convert(sys.stdin.read()))
