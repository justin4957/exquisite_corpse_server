/// Database schema migrations for the exquisite corpse server.
import sqlight

/// Runs all migrations to set up the database schema.
pub fn run(connection: sqlight.Connection) -> Result(Nil, sqlight.Error) {
  sqlight.exec(
    "
    CREATE TABLE IF NOT EXISTS poems (
      id TEXT PRIMARY KEY,
      total_lines INTEGER NOT NULL DEFAULT 11,
      status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','complete','revealed')),
      title TEXT NOT NULL DEFAULT '',
      seed_line TEXT NOT NULL,
      version INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS poem_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      poem_id TEXT NOT NULL REFERENCES poems(id) ON DELETE CASCADE,
      line_number INTEGER NOT NULL,
      full_text TEXT NOT NULL,
      visible_hint TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(poem_id, line_number)
    );

    CREATE INDEX IF NOT EXISTS idx_poem_lines_poem_id ON poem_lines(poem_id);
    CREATE INDEX IF NOT EXISTS idx_poems_status ON poems(status);
    ",
    on: connection,
  )
}
