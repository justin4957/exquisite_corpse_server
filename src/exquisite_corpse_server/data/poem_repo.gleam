/// CRUD operations for the poems table.
import exquisite_corpse_server/core/poem_id
import exquisite_corpse_server/core/poem_status
import gleam/dynamic/decode
import gleam/option.{type Option}
import sqlight

/// A poem record as stored in the database.
pub type Poem {
  Poem(
    id: String,
    total_lines: Int,
    status: poem_status.PoemStatus,
    title: String,
    seed_line: String,
    version: Int,
    created_at: String,
    updated_at: String,
  )
}

/// A lightweight poem summary for list views.
pub type PoemSummary {
  PoemSummary(
    id: String,
    total_lines: Int,
    current_line_count: Int,
    status: String,
    seed_line: String,
    created_at: String,
  )
}

/// Creates a new poem and returns the generated ID.
pub fn create(
  connection: sqlight.Connection,
  total_lines: Int,
  seed_line: String,
  seed_hint: String,
) -> Result(Poem, sqlight.Error) {
  let generated_id = poem_id.generate()
  let id_string = poem_id.to_string(generated_id)

  // Insert the poem record
  use _ <- result_try(sqlight.query(
    "INSERT INTO poems (id, total_lines, seed_line) VALUES (?, ?, ?)
     RETURNING id, total_lines, status, title, seed_line, version, created_at, updated_at",
    on: connection,
    with: [sqlight.text(id_string), sqlight.int(total_lines), sqlight.text(seed_line)],
    expecting: poem_decoder(),
  ))

  // Insert seed line as line_number 1
  use _ <- result_try(sqlight.query(
    "INSERT INTO poem_lines (poem_id, line_number, full_text, visible_hint) VALUES (?, 1, ?, ?)",
    on: connection,
    with: [sqlight.text(id_string), sqlight.text(seed_line), sqlight.text(seed_hint)],
    expecting: decode.success(Nil),
  ))

  // Return the created poem
  case get_by_id(connection, id_string) {
    Ok(poem) -> Ok(poem)
    Error(error) -> Error(error)
  }
}

/// Fetches a single poem by ID.
pub fn get_by_id(
  connection: sqlight.Connection,
  poem_id: String,
) -> Result(Poem, sqlight.Error) {
  case
    sqlight.query(
      "SELECT id, total_lines, status, title, seed_line, version, created_at, updated_at
       FROM poems WHERE id = ?",
      on: connection,
      with: [sqlight.text(poem_id)],
      expecting: poem_decoder(),
    )
  {
    Ok([poem]) -> Ok(poem)
    Ok(_) ->
      Error(sqlight.SqlightError(sqlight.Notfound, "Poem not found", -1))
    Error(error) -> Error(error)
  }
}

/// Lists poems with optional status filter, ordered by creation date descending.
pub fn list(
  connection: sqlight.Connection,
  status_filter: Option(String),
) -> Result(List(PoemSummary), sqlight.Error) {
  case status_filter {
    option.Some(status_value) ->
      sqlight.query(
        "SELECT p.id, p.total_lines,
                (SELECT COUNT(*) FROM poem_lines WHERE poem_id = p.id) as current_line_count,
                p.status, p.seed_line, p.created_at
         FROM poems p
         WHERE p.status = ?
         ORDER BY p.created_at DESC",
        on: connection,
        with: [sqlight.text(status_value)],
        expecting: poem_summary_decoder(),
      )
    option.None ->
      sqlight.query(
        "SELECT p.id, p.total_lines,
                (SELECT COUNT(*) FROM poem_lines WHERE poem_id = p.id) as current_line_count,
                p.status, p.seed_line, p.created_at
         FROM poems p
         ORDER BY p.created_at DESC",
        on: connection,
        with: [],
        expecting: poem_summary_decoder(),
      )
  }
}

/// Increments the poem version using optimistic locking.
/// Returns Ok(Nil) if successful, Error if version mismatch (conflict).
pub fn increment_version(
  connection: sqlight.Connection,
  poem_id: String,
  expected_version: Int,
) -> Result(Nil, sqlight.Error) {
  use rows <- result_try(sqlight.query(
    "UPDATE poems SET version = version + 1, updated_at = datetime('now')
     WHERE id = ? AND version = ?
     RETURNING id",
    on: connection,
    with: [sqlight.text(poem_id), sqlight.int(expected_version)],
    expecting: decode.at([0], decode.string),
  ))
  case rows {
    [_] -> Ok(Nil)
    _ ->
      Error(sqlight.SqlightError(
        sqlight.Busy,
        "Version conflict: poem has been modified",
        -1,
      ))
  }
}

/// Updates poem status.
pub fn update_status(
  connection: sqlight.Connection,
  poem_id: String,
  new_status: poem_status.PoemStatus,
) -> Result(Nil, sqlight.Error) {
  use rows <- result_try(sqlight.query(
    "UPDATE poems SET status = ?, updated_at = datetime('now')
     WHERE id = ?
     RETURNING id",
    on: connection,
    with: [
      sqlight.text(poem_status.to_string(new_status)),
      sqlight.text(poem_id),
    ],
    expecting: decode.at([0], decode.string),
  ))
  case rows {
    [_] -> Ok(Nil)
    _ ->
      Error(sqlight.SqlightError(sqlight.Notfound, "Poem not found", -1))
  }
}

/// Sets the poem title.
pub fn set_title(
  connection: sqlight.Connection,
  poem_id: String,
  title: String,
) -> Result(Nil, sqlight.Error) {
  use rows <- result_try(sqlight.query(
    "UPDATE poems SET title = ?, updated_at = datetime('now')
     WHERE id = ?
     RETURNING id",
    on: connection,
    with: [sqlight.text(title), sqlight.text(poem_id)],
    expecting: decode.at([0], decode.string),
  ))
  case rows {
    [_] -> Ok(Nil)
    _ ->
      Error(sqlight.SqlightError(sqlight.Notfound, "Poem not found", -1))
  }
}

fn poem_decoder() -> decode.Decoder(Poem) {
  use id <- decode.field(0, decode.string)
  use total_lines <- decode.field(1, decode.int)
  use status <- decode.field(2, poem_status.decoder())
  use title <- decode.field(3, decode.string)
  use seed_line <- decode.field(4, decode.string)
  use version <- decode.field(5, decode.int)
  use created_at <- decode.field(6, decode.string)
  use updated_at <- decode.field(7, decode.string)
  decode.success(Poem(
    id: id,
    total_lines: total_lines,
    status: status,
    title: title,
    seed_line: seed_line,
    version: version,
    created_at: created_at,
    updated_at: updated_at,
  ))
}

fn poem_summary_decoder() -> decode.Decoder(PoemSummary) {
  use id <- decode.field(0, decode.string)
  use total_lines <- decode.field(1, decode.int)
  use current_line_count <- decode.field(2, decode.int)
  use status <- decode.field(3, decode.string)
  use seed_line <- decode.field(4, decode.string)
  use created_at <- decode.field(5, decode.string)
  decode.success(PoemSummary(
    id: id,
    total_lines: total_lines,
    current_line_count: current_line_count,
    status: status,
    seed_line: seed_line,
    created_at: created_at,
  ))
}

/// Helper to chain Result operations consistently.
fn result_try(
  result: Result(a, e),
  next: fn(a) -> Result(b, e),
) -> Result(b, e) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}
