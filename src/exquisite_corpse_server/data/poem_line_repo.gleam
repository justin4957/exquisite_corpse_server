/// CRUD operations for the poem_lines table.
import gleam/dynamic/decode
import sqlight

/// A poem line record as stored in the database.
pub type PoemLineRecord {
  PoemLineRecord(
    id: Int,
    poem_id: String,
    line_number: Int,
    full_text: String,
    visible_hint: String,
    created_at: String,
  )
}

/// Adds a new line to a poem.
pub fn add_line(
  connection: sqlight.Connection,
  poem_id: String,
  line_number: Int,
  full_text: String,
  visible_hint: String,
) -> Result(PoemLineRecord, sqlight.Error) {
  case
    sqlight.query(
      "INSERT INTO poem_lines (poem_id, line_number, full_text, visible_hint)
       VALUES (?, ?, ?, ?)
       RETURNING id, poem_id, line_number, full_text, visible_hint, created_at",
      on: connection,
      with: [
        sqlight.text(poem_id),
        sqlight.int(line_number),
        sqlight.text(full_text),
        sqlight.text(visible_hint),
      ],
      expecting: poem_line_decoder(),
    )
  {
    Ok([line]) -> Ok(line)
    Ok(_) ->
      Error(sqlight.SqlightError(
        sqlight.GenericError,
        "Failed to insert line",
        -1,
      ))
    Error(error) -> Error(error)
  }
}

/// Gets all lines for a poem, ordered by line_number.
pub fn get_lines_for_poem(
  connection: sqlight.Connection,
  poem_id: String,
) -> Result(List(PoemLineRecord), sqlight.Error) {
  sqlight.query(
    "SELECT id, poem_id, line_number, full_text, visible_hint, created_at
     FROM poem_lines
     WHERE poem_id = ?
     ORDER BY line_number ASC",
    on: connection,
    with: [sqlight.text(poem_id)],
    expecting: poem_line_decoder(),
  )
}

/// Gets the count of lines for a poem.
pub fn count_lines(
  connection: sqlight.Connection,
  poem_id: String,
) -> Result(Int, sqlight.Error) {
  case
    sqlight.query(
      "SELECT COUNT(*) FROM poem_lines WHERE poem_id = ?",
      on: connection,
      with: [sqlight.text(poem_id)],
      expecting: decode.at([0], decode.int),
    )
  {
    Ok([count]) -> Ok(count)
    Ok(_) -> Ok(0)
    Error(error) -> Error(error)
  }
}

/// Gets the last line for a poem (highest line_number).
pub fn get_last_line(
  connection: sqlight.Connection,
  poem_id: String,
) -> Result(PoemLineRecord, sqlight.Error) {
  case
    sqlight.query(
      "SELECT id, poem_id, line_number, full_text, visible_hint, created_at
       FROM poem_lines
       WHERE poem_id = ?
       ORDER BY line_number DESC
       LIMIT 1",
      on: connection,
      with: [sqlight.text(poem_id)],
      expecting: poem_line_decoder(),
    )
  {
    Ok([line]) -> Ok(line)
    Ok(_) -> Error(sqlight.SqlightError(sqlight.Notfound, "No lines found", -1))
    Error(error) -> Error(error)
  }
}

fn poem_line_decoder() -> decode.Decoder(PoemLineRecord) {
  use id <- decode.field(0, decode.int)
  use poem_id <- decode.field(1, decode.string)
  use line_number <- decode.field(2, decode.int)
  use full_text <- decode.field(3, decode.string)
  use visible_hint <- decode.field(4, decode.string)
  use created_at <- decode.field(5, decode.string)
  decode.success(PoemLineRecord(
    id: id,
    poem_id: poem_id,
    line_number: line_number,
    full_text: full_text,
    visible_hint: visible_hint,
    created_at: created_at,
  ))
}
