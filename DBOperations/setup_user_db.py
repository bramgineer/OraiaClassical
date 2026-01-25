#!/usr/bin/env python3
import argparse
import os
import sqlite3


USER_SCHEMA_SQL = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS vocabulary_list (
  title TEXT PRIMARY KEY,
  description TEXT
);

CREATE TABLE IF NOT EXISTS vocabulary_list_entry (
  vocabulary_list TEXT NOT NULL,
  lemma INTEGER NOT NULL,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (vocabulary_list, lemma),
  FOREIGN KEY (vocabulary_list) REFERENCES vocabulary_list(title) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS lemma_user_state (
  lemma INTEGER PRIMARY KEY,
  is_favorite INTEGER,
  learning_status INTEGER,
  updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_vocab_list_entry_list ON vocabulary_list_entry(vocabulary_list);
CREATE INDEX IF NOT EXISTS idx_user_state_favorite ON lemma_user_state(is_favorite);
CREATE INDEX IF NOT EXISTS idx_user_state_status ON lemma_user_state(learning_status);
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Create user_data.sqlite for Oraia Classical.")
    parser.add_argument("--db", default="user_data.sqlite", help="Output SQLite DB path")
    args = parser.parse_args()

    db_path = os.path.abspath(args.db)
    os.makedirs(os.path.dirname(db_path), exist_ok=True)

    conn = sqlite3.connect(db_path)
    try:
        conn.executescript(USER_SCHEMA_SQL)
        conn.commit()
    finally:
        conn.close()

    print(f"Created {db_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
