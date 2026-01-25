#!/usr/bin/env python3
import argparse
import sqlite3


def main() -> int:
    parser = argparse.ArgumentParser(description="Sanity-check forms in the SQLite DB.")
    parser.add_argument("--db", default="ag_db.sqlite", help="SQLite DB path (default: ag_db.sqlite)")
    parser.add_argument("--form", required=True, help="Exact form string to look up")
    args = parser.parse_args()

    conn = sqlite3.connect(args.db)
    try:
        sql = """
        SELECT lemma.headword,
               pos.code,
               form.form,
               form.tense,
               form.mood,
               form.voice,
               form.person,
               form.number,
               form.grammatical_case,
               form.gender,
               form.verb_form_type,
               dialect.code,
               form.source,
               form.tags
        FROM form
        JOIN lemma ON form.lemma_id = lemma.id
        JOIN pos ON form.pos_id = pos.id
        LEFT JOIN dialect ON form.dialect_id = dialect.id
        WHERE form.form = ?
        ORDER BY lemma.headword, pos.code, form.id;
        """
        rows = conn.execute(sql, (args.form,)).fetchall()
        if not rows:
            print("No rows found.")
            return 1

        for row in rows:
            (
                headword,
                pos_code,
                form_text,
                tense,
                mood,
                voice,
                person,
                number,
                grammatical_case,
                gender,
                verb_form_type,
                dialect,
                source,
                tags,
            ) = row
            print("-" * 60)
            print(f"lemma: {headword}  pos: {pos_code}")
            print(f"form: {form_text}")
            print(f"tense: {tense}  mood: {mood}  voice: {voice}")
            print(f"person: {person}  number: {number}")
            print(f"case: {grammatical_case}  gender: {gender}  verb_form_type: {verb_form_type}")
            print(f"dialect: {dialect}  source: {source}")
            if tags is not None:
                print(f"tags: {tags}")
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
