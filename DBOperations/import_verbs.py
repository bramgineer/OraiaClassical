#!/usr/bin/env python3
import argparse
import json
import os
import sqlite3
from typing import Dict, Iterable, List, Optional, Set, Tuple


SCHEMA_SQL = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS lemma (
  id              INTEGER PRIMARY KEY,
  headword        TEXT NOT NULL,
  headword_norm   TEXT NOT NULL,
  sort_key        TEXT,
  notes           TEXT,
  etymology_text  TEXT,
  etymology_templates TEXT,
  etymology_number INTEGER,
  inflection_templates TEXT,
  related         TEXT,
  synonyms        TEXT,
  antonyms        TEXT,
  categories      TEXT,
  entry_extra     TEXT
);

CREATE TABLE IF NOT EXISTS pos (
  id    INTEGER PRIMARY KEY,
  code  TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS lemma_pos (
  lemma_id  INTEGER NOT NULL REFERENCES lemma(id) ON DELETE CASCADE,
  pos_id    INTEGER NOT NULL REFERENCES pos(id),
  is_primary INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (lemma_id, pos_id)
);

CREATE TABLE IF NOT EXISTS sense (
  id            INTEGER PRIMARY KEY,
  lemma_id      INTEGER NOT NULL REFERENCES lemma(id) ON DELETE CASCADE,
  pos_id        INTEGER REFERENCES pos(id),
  gloss         TEXT NOT NULL,
  definition    TEXT,
  sense_order   INTEGER NOT NULL DEFAULT 0,
  tags          TEXT,
  form_of       TEXT,
  alt_of        TEXT,
  qualifier     TEXT,
  categories    TEXT,
  raw_glosses   TEXT,
  raw_tags      TEXT,
  links         TEXT,
  topics        TEXT,
  examples      TEXT,
  sense_extra   TEXT
);

CREATE TABLE IF NOT EXISTS dialect (
  id    INTEGER PRIMARY KEY,
  code  TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS form (
  id              INTEGER PRIMARY KEY,
  lemma_id         INTEGER NOT NULL REFERENCES lemma(id) ON DELETE CASCADE,
  pos_id           INTEGER NOT NULL REFERENCES pos(id),
  form             TEXT NOT NULL,
  form_norm        TEXT NOT NULL,
  dialect_id       INTEGER REFERENCES dialect(id),
  tense            TEXT,
  mood             TEXT,
  voice            TEXT,
  person           TEXT,
  number           TEXT,
  grammatical_case TEXT,
  gender           TEXT,
  degree           TEXT,
  verb_form_type   TEXT,
  is_principal_part INTEGER NOT NULL DEFAULT 0,
  pronoun_type     TEXT,
  governs_case     TEXT,
  tags             TEXT,
  source           TEXT
);

CREATE INDEX IF NOT EXISTS idx_lemma_headword_norm ON lemma(headword_norm);
CREATE INDEX IF NOT EXISTS idx_form_form_norm ON form(form_norm);
CREATE INDEX IF NOT EXISTS idx_form_lemma_pos ON form(lemma_id, pos_id);
CREATE INDEX IF NOT EXISTS idx_form_features_verb ON form(pos_id, tense, mood, voice, person, number);
CREATE INDEX IF NOT EXISTS idx_form_features_nominal ON form(pos_id, grammatical_case, gender, number);
"""


DIALECT_TAGS = {
    "attic": "attic",
    "ionic": "ionic",
    "epic": "epic",
    "homeric": "homeric",
    "koine": "koine",
    "byzantine": "byzantine",
    "doric": "doric",
    "aeolic": "aeolic",
}

CASE_TAGS = {
    "nominative": "nominative",
    "genitive": "genitive",
    "dative": "dative",
    "accusative": "accusative",
    "vocative": "vocative",
}

NUMBER_TAGS = {
    "singular": "singular",
    "dual": "dual",
    "plural": "plural",
}

GENDER_TAGS = {
    "masculine": "masculine",
    "feminine": "feminine",
    "neuter": "neuter",
}

PERSON_TAGS = {
    "first-person": "first-person",
    "second-person": "second-person",
    "third-person": "third-person",
}

TENSE_TAGS = {
    "present": "present",
    "imperfect": "imperfect",
    "future": "future",
    "aorist": "aorist",
    "perfect": "perfect",
    "pluperfect": "pluperfect",
    "future-perfect": "future-perfect",
}

MOOD_TAGS = {
    "indicative": "indicative",
    "imperative": "imperative",
    "subjunctive": "subjunctive",
    "optative": "optative",
}

VOICE_TAGS = {
    "active": "active",
    "middle": "middle",
    "passive": "passive",
    "middle-passive": "middle-passive",
}

DEGREE_TAGS = {
    "positive": "positive",
    "comparative": "comparative",
    "superlative": "superlative",
}

VERB_FORM_TAGS = {
    "finite": "finite",
    "infinitive": "infinitive",
    "participle": "participle",
}

PRONOUN_TYPE_KEYWORDS = [
    "personal",
    "demonstrative",
    "relative",
    "interrogative",
    "indefinite",
    "reflexive",
    "reciprocal",
    "possessive",
    "proximal",
    "medial",
    "distal",
]

POS_ALIASES = {
    "adjective": "adj",
    "adj": "adj",
    "adverb": "adv",
    "adv": "adv",
    "pronoun": "pron",
    "pron": "pron",
    "preposition": "prep",
    "prep": "prep",
    "conjunction": "conj",
    "conj": "conj",
    "interjection": "intj",
    "intj": "intj",
    "determiner": "det",
    "det": "det",
    "article": "article",
    "particle": "particle",
    "noun": "noun",
    "verb": "verb",
    "number": "num",
    "num": "num",
    "proper noun": "name",
    "name": "name",
    "prefix": "prefix",
    "suffix": "suffix",
    "postposition": "postp",
    "postp": "postp",
}

LEMMA_EXTRA_COLUMNS = {
    "etymology_text": "TEXT",
    "etymology_templates": "TEXT",
    "etymology_number": "INTEGER",
    "inflection_templates": "TEXT",
    "related": "TEXT",
    "synonyms": "TEXT",
    "antonyms": "TEXT",
    "categories": "TEXT",
    "entry_extra": "TEXT",
}

SENSE_EXTRA_COLUMNS = {
    "tags": "TEXT",
    "form_of": "TEXT",
    "alt_of": "TEXT",
    "qualifier": "TEXT",
    "categories": "TEXT",
    "raw_glosses": "TEXT",
    "raw_tags": "TEXT",
    "links": "TEXT",
    "topics": "TEXT",
    "examples": "TEXT",
    "sense_extra": "TEXT",
}

FORM_EXTRA_COLUMNS = {
    "source": "TEXT",
}

ENTRY_EXTRA_KEYS = {
    "pos",
    "word",
    "lang",
    "lang_code",
    "senses",
    "forms",
    "etymology_text",
    "etymology_templates",
    "etymology_number",
    "inflection_templates",
    "related",
    "synonyms",
    "antonyms",
    "categories",
}

SENSE_EXTRA_KEYS = {
    "id",
    "glosses",
    "tags",
    "form_of",
    "alt_of",
    "qualifier",
    "categories",
    "raw_glosses",
    "raw_tags",
    "links",
    "topics",
    "examples",
}


def normalize(text: str) -> str:
    return text.lower()


def dumps_or_none(value) -> Optional[str]:
    if value is None:
        return None
    if isinstance(value, (list, dict)):
        if not value:
            return None
        return json.dumps(value, ensure_ascii=True)
    if isinstance(value, str) and not value:
        return None
    return value


def ensure_columns(conn: sqlite3.Connection, table: str, columns: Dict[str, str]) -> None:
    existing = {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}
    for name, col_def in columns.items():
        if name not in existing:
            conn.execute(f"ALTER TABLE {table} ADD COLUMN {name} {col_def}")


def ensure_schema_columns(conn: sqlite3.Connection) -> None:
    ensure_columns(conn, "lemma", LEMMA_EXTRA_COLUMNS)
    ensure_columns(conn, "sense", SENSE_EXTRA_COLUMNS)
    ensure_columns(conn, "form", FORM_EXTRA_COLUMNS)


def parse_tags(tags: Iterable[str]) -> Dict[str, Optional[str]]:
    tags_lc = {t.lower() for t in tags}

    def pick(mapping: Dict[str, str]) -> Optional[str]:
        for key, value in mapping.items():
            if key in tags_lc:
                return value
        return None

    return {
        "dialect": pick(DIALECT_TAGS),
        "case": pick(CASE_TAGS),
        "number": pick(NUMBER_TAGS),
        "gender": pick(GENDER_TAGS),
        "person": pick(PERSON_TAGS),
        "tense": pick(TENSE_TAGS),
        "mood": pick(MOOD_TAGS),
        "voice": pick(VOICE_TAGS),
        "degree": pick(DEGREE_TAGS),
        "verb_form_type": pick(VERB_FORM_TAGS),
    }


def should_keep_form(form_entry: Dict) -> bool:
    if not form_entry.get("form"):
        return False
    if form_entry.get("form") == "-":
        return False
    tags = [t.lower() for t in form_entry.get("tags", [])]
    if not tags:
        return False
    if "romanization" in tags:
        return False
    if "inflection-template" in tags or "table-tags" in tags or "class" in tags:
        return False
    return True


def extract_pronoun_type(entry: Dict) -> Optional[str]:
    candidates: List[str] = []
    for head in entry.get("head_templates") or []:
        args = head.get("args") or {}
        for key, value in args.items():
            if not isinstance(value, str):
                continue
            if key.startswith("cat"):
                candidates.append(value)
    for sense in entry.get("senses") or []:
        for tag in sense.get("tags") or []:
            candidates.append(str(tag))

    candidates_lc = " ".join(candidates).lower()
    for keyword in PRONOUN_TYPE_KEYWORDS:
        if keyword in candidates_lc:
            return keyword
    return None


def extract_governs_case(entry: Dict) -> Optional[str]:
    cases: List[str] = []

    def add_case(raw: str) -> None:
        raw = raw.strip().lower()
        mapping = {
            "gen": "genitive",
            "genitive": "genitive",
            "dat": "dative",
            "dative": "dative",
            "acc": "accusative",
            "accusative": "accusative",
        }
        if raw in mapping:
            case = mapping[raw]
            if case not in cases:
                cases.append(case)

    for sense in entry.get("senses") or []:
        for tag in sense.get("tags") or []:
            tag_lc = str(tag).lower()
            if tag_lc.startswith("with-"):
                add_case(tag_lc.replace("with-", ""))

    for head in entry.get("head_templates") or []:
        args = head.get("args") or {}
        value = args.get("2")
        if not isinstance(value, str):
            continue
        parts = value.replace(";", "/").replace(",", "/").split("/")
        for part in parts:
            add_case(part)

    if not cases:
        return None
    return "/".join(cases)


def ensure_pos(conn: sqlite3.Connection, code: str, pos_cache: Dict[str, int]) -> int:
    if code in pos_cache:
        return pos_cache[code]
    cur = conn.execute("SELECT id FROM pos WHERE code = ?", (code,))
    row = cur.fetchone()
    if row:
        pos_cache[code] = row[0]
        return row[0]
    cur = conn.execute("INSERT INTO pos (code) VALUES (?)", (code,))
    pos_cache[code] = cur.lastrowid
    return cur.lastrowid


def ensure_dialect(conn: sqlite3.Connection, code: str, dialect_cache: Dict[str, int]) -> int:
    if code in dialect_cache:
        return dialect_cache[code]
    cur = conn.execute("SELECT id FROM dialect WHERE code = ?", (code,))
    row = cur.fetchone()
    if row:
        dialect_cache[code] = row[0]
        return row[0]
    cur = conn.execute("INSERT INTO dialect (code) VALUES (?)", (code,))
    dialect_cache[code] = cur.lastrowid
    return cur.lastrowid


def ensure_lemma(
    conn: sqlite3.Connection,
    headword: str,
    lemma_cache: Dict[Tuple[str, str], int],
) -> int:
    headword_norm = normalize(headword)
    key = (headword, headword_norm)
    if key in lemma_cache:
        return lemma_cache[key]
    cur = conn.execute(
        "SELECT id FROM lemma WHERE headword = ? AND headword_norm = ?",
        (headword, headword_norm),
    )
    row = cur.fetchone()
    if row:
        lemma_cache[key] = row[0]
        return row[0]
    cur = conn.execute(
        "INSERT INTO lemma (headword, headword_norm) VALUES (?, ?)",
        (headword, headword_norm),
    )
    lemma_cache[key] = cur.lastrowid
    return cur.lastrowid


def extract_gloss(sense: Dict) -> Tuple[str, Optional[str]]:
    glosses = sense.get("glosses") or []
    if not glosses:
        return "?", None
    gloss = glosses[0]
    definition = "; ".join(glosses[1:]) if len(glosses) > 1 else None
    return gloss, definition


def extract_entry_metadata(entry: Dict) -> Dict[str, Optional[object]]:
    etymology_text = entry.get("etymology_text")
    etymology_templates = dumps_or_none(entry.get("etymology_templates"))
    etymology_number = entry.get("etymology_number")
    inflection_templates = dumps_or_none(entry.get("inflection_templates"))
    related = dumps_or_none(entry.get("related"))
    synonyms = dumps_or_none(entry.get("synonyms"))
    antonyms = dumps_or_none(entry.get("antonyms"))
    categories = dumps_or_none(entry.get("categories"))

    extra = {k: v for k, v in entry.items() if k not in ENTRY_EXTRA_KEYS}
    entry_extra = dumps_or_none(extra)

    return {
        "etymology_text": etymology_text,
        "etymology_templates": etymology_templates,
        "etymology_number": etymology_number,
        "inflection_templates": inflection_templates,
        "related": related,
        "synonyms": synonyms,
        "antonyms": antonyms,
        "categories": categories,
        "entry_extra": entry_extra,
    }


def extract_sense_metadata(sense: Dict) -> Dict[str, Optional[str]]:
    tags = dumps_or_none(sense.get("tags"))
    form_of = dumps_or_none(sense.get("form_of"))
    alt_of = dumps_or_none(sense.get("alt_of"))
    qualifier = sense.get("qualifier") if isinstance(sense.get("qualifier"), str) else None
    categories = dumps_or_none(sense.get("categories"))
    raw_glosses = dumps_or_none(sense.get("raw_glosses"))
    raw_tags = dumps_or_none(sense.get("raw_tags"))
    links = dumps_or_none(sense.get("links"))
    topics = dumps_or_none(sense.get("topics"))
    examples = dumps_or_none(sense.get("examples"))

    extra = {k: v for k, v in sense.items() if k not in SENSE_EXTRA_KEYS}
    sense_extra = dumps_or_none(extra)

    return {
        "tags": tags,
        "form_of": form_of,
        "alt_of": alt_of,
        "qualifier": qualifier,
        "categories": categories,
        "raw_glosses": raw_glosses,
        "raw_tags": raw_tags,
        "links": links,
        "topics": topics,
        "examples": examples,
        "sense_extra": sense_extra,
    }


def update_lemma_metadata(conn: sqlite3.Connection, lemma_id: int, metadata: Dict[str, Optional[object]]) -> None:
    if not any(value is not None for value in metadata.values()):
        return
    conn.execute(
        """
        UPDATE lemma SET
            etymology_text = COALESCE(?, etymology_text),
            etymology_templates = COALESCE(?, etymology_templates),
            etymology_number = COALESCE(?, etymology_number),
            inflection_templates = COALESCE(?, inflection_templates),
            related = COALESCE(?, related),
            synonyms = COALESCE(?, synonyms),
            antonyms = COALESCE(?, antonyms),
            categories = COALESCE(?, categories),
            entry_extra = COALESCE(?, entry_extra)
        WHERE id = ?
        """,
        (
            metadata["etymology_text"],
            metadata["etymology_templates"],
            metadata["etymology_number"],
            metadata["inflection_templates"],
            metadata["related"],
            metadata["synonyms"],
            metadata["antonyms"],
            metadata["categories"],
            metadata["entry_extra"],
            lemma_id,
        ),
    )


def import_jsonl(
    conn: sqlite3.Connection,
    jsonl_path: str,
    allowed_pos: Set[str],
    commit_every: int = 1000,
) -> None:
    pos_cache: Dict[str, int] = {}
    dialect_cache: Dict[str, int] = {}
    lemma_cache: Dict[Tuple[str, str], int] = {}

    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")

    inserted = 0
    skipped_pos_counts: Dict[str, int] = {}
    skipped_reasons: Dict[str, int] = {
        "json_decode_error": 0,
        "non_grc": 0,
        "missing_pos": 0,
        "pos_not_allowed": 0,
        "missing_headword": 0,
    }
    with open(jsonl_path, "r", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                skipped_reasons["json_decode_error"] += 1
                continue

            if entry.get("lang_code") != "grc":
                skipped_reasons["non_grc"] += 1
                continue
            pos_code = (entry.get("pos") or "").strip()
            if not pos_code:
                skipped_reasons["missing_pos"] += 1
                continue
            if pos_code not in allowed_pos:
                skipped_reasons["pos_not_allowed"] += 1
                skipped_pos_counts[pos_code] = skipped_pos_counts.get(pos_code, 0) + 1
                continue

            headword = entry.get("word")
            if not headword:
                skipped_reasons["missing_headword"] += 1
                continue

            entry_metadata = extract_entry_metadata(entry)
            pos_id = ensure_pos(conn, pos_code, pos_cache)
            lemma_id = ensure_lemma(conn, headword, lemma_cache)
            update_lemma_metadata(conn, lemma_id, entry_metadata)
            pronoun_type = extract_pronoun_type(entry) if pos_code == "pron" else None
            governs_case = extract_governs_case(entry) if pos_code == "prep" else None

            conn.execute(
                "INSERT OR IGNORE INTO lemma_pos (lemma_id, pos_id, is_primary) VALUES (?, ?, ?)",
                (lemma_id, pos_id, 1),
            )

            senses = entry.get("senses") or []
            for idx, sense in enumerate(senses):
                gloss, definition = extract_gloss(sense)
                sense_metadata = extract_sense_metadata(sense)
                conn.execute(
                    """
                    INSERT INTO sense (
                        lemma_id, pos_id, gloss, definition, sense_order,
                        tags, form_of, alt_of, qualifier, categories,
                        raw_glosses, raw_tags, links, topics, examples, sense_extra
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        lemma_id,
                        pos_id,
                        gloss,
                        definition,
                        idx,
                        sense_metadata["tags"],
                        sense_metadata["form_of"],
                        sense_metadata["alt_of"],
                        sense_metadata["qualifier"],
                        sense_metadata["categories"],
                        sense_metadata["raw_glosses"],
                        sense_metadata["raw_tags"],
                        sense_metadata["links"],
                        sense_metadata["topics"],
                        sense_metadata["examples"],
                        sense_metadata["sense_extra"],
                    ),
                )

            for form_entry in entry.get("forms") or []:
                if not should_keep_form(form_entry):
                    continue

                form_text = form_entry.get("form")
                form_norm = normalize(form_text)
                tags = form_entry.get("tags") or []
                parsed = parse_tags(tags)

                dialect_id = None
                if parsed["dialect"]:
                    dialect_id = ensure_dialect(conn, parsed["dialect"], dialect_cache)

                conn.execute(
                    """
                    INSERT INTO form (
                        lemma_id, pos_id, form, form_norm, dialect_id,
                        tense, mood, voice, person, number,
                        grammatical_case, gender, degree,
                        verb_form_type, is_principal_part,
                        pronoun_type, governs_case, tags, source
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        lemma_id,
                        pos_id,
                        form_text,
                        form_norm,
                        dialect_id,
                        parsed["tense"],
                        parsed["mood"],
                        parsed["voice"],
                        parsed["person"],
                        parsed["number"],
                        parsed["case"],
                        parsed["gender"],
                        parsed["degree"],
                        parsed["verb_form_type"],
                        0,
                        pronoun_type,
                        governs_case,
                        json.dumps(tags, ensure_ascii=True),
                        form_entry.get("source"),
                    ),
                )

            inserted += 1
            if inserted % commit_every == 0:
                conn.commit()

    conn.commit()
    report_skip_summary(skipped_pos_counts, skipped_reasons)


def report_skip_summary(skipped_pos_counts: Dict[str, int], skipped_reasons: Dict[str, int]) -> None:
    total_skipped_pos = sum(skipped_pos_counts.values())
    if not skipped_reasons and not skipped_pos_counts:
        return
    print("\nSkip report")
    print("-" * 40)
    for key, value in skipped_reasons.items():
        print(f"{key}: {value}")
    if total_skipped_pos:
        print("\nSkipped POS breakdown")
        for pos_code, count in sorted(skipped_pos_counts.items(), key=lambda kv: (-kv[1], kv[0])):
            print(f"{pos_code}: {count}")


def create_db_if_missing(db_path: str) -> sqlite3.Connection:
    db_dir = os.path.dirname(os.path.abspath(db_path))
    if db_dir and not os.path.exists(db_dir):
        os.makedirs(db_dir, exist_ok=True)
    new_db = not os.path.exists(db_path)
    if new_db:
        open(db_path, "a").close()
    conn = sqlite3.connect(db_path)
    if new_db:
        conn.executescript(SCHEMA_SQL)
    else:
        conn.executescript(SCHEMA_SQL)
    ensure_schema_columns(conn)
    return conn


def parse_pos_list(pos_list: str) -> Set[str]:
    result: Set[str] = set()
    for item in pos_list.split(","):
        raw = item.strip().lower()
        if not raw:
            continue
        mapped = POS_ALIASES.get(raw, raw)
        result.add(mapped)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Import AncientGreek-2.jsonl into SQLite.")
    parser.add_argument(
        "--db",
        default="ag_db.sqlite",
        help="SQLite DB path (default: ag_db.sqlite)",
    )
    parser.add_argument(
        "--input",
        default="AncientGreek-2.jsonl",
        help="Path to AncientGreek-2.jsonl (default: AncientGreek-2.jsonl)",
    )
    parser.add_argument(
        "--pos",
        default="noun,verb,adjective,adverb,pronoun,particle,article,preposition,conjunction,suffix,prefix,intj,det",
        help="Comma-separated POS codes to import",
    )
    parser.add_argument(
        "--commit-every",
        type=int,
        default=1000,
        help="Commit every N entries (default: 1000)",
    )
    args = parser.parse_args()

    allowed_pos = parse_pos_list(args.pos)
    if not allowed_pos:
        raise SystemExit("POS set is empty. Provide --pos.")

    conn = create_db_if_missing(args.db)
    try:
        import_jsonl(conn, args.input, allowed_pos, commit_every=args.commit_every)
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
