import exquisite_corpse_server/core/poem
import exquisite_corpse_server/core/poem_id
import exquisite_corpse_server/core/poem_status
import exquisite_corpse_server/data/database
import exquisite_corpse_server/data/migration
import exquisite_corpse_server/data/poem_line_repo
import exquisite_corpse_server/data/poem_repo
import exquisite_corpse_server/web/context.{type Context, Context}
import exquisite_corpse_server/web/middleware
import exquisite_corpse_server/web/router
import gleam/http
import gleam/json
import gleam/list
import gleam/option
import gleam/string
import gleeunit
import sqlight
import wisp/simulate

pub fn main() -> Nil {
  gleeunit.main()
}

// --- Test helpers ---

/// Creates an in-memory SQLite connection with schema for testing.
fn setup_test_db() -> sqlight.Connection {
  let assert Ok(connection) = sqlight.open(":memory:")
  let assert Ok(_) = sqlight.exec("PRAGMA foreign_keys=ON;", on: connection)
  let assert Ok(_) = migration.run(connection)
  connection
}

fn test_context(connection: sqlight.Connection) -> Context {
  Context(db_connection: connection, static_directory: "/tmp/nonexistent")
}

fn handle_request(request, ctx: Context) {
  middleware.apply(request, ctx, fn(req) { router.handle_request(req, ctx) })
}

// --- Domain logic tests ---

pub fn poem_id_generates_unique_ids_test() {
  let first_id = poem_id.generate()
  let second_id = poem_id.generate()
  assert poem_id.to_string(first_id) != poem_id.to_string(second_id)
}

pub fn poem_id_has_expected_length_test() {
  let generated_id = poem_id.generate()
  let id_string = poem_id.to_string(generated_id)
  assert string.length(id_string) == 12
}

pub fn poem_id_roundtrip_test() {
  let original_id = poem_id.generate()
  let id_string = poem_id.to_string(original_id)
  let restored_id = poem_id.from_string(id_string)
  assert poem_id.to_string(restored_id) == id_string
}

pub fn poem_status_to_string_test() {
  assert poem_status.to_string(poem_status.Active) == "active"
  assert poem_status.to_string(poem_status.Complete) == "complete"
  assert poem_status.to_string(poem_status.Revealed) == "revealed"
}

pub fn poem_status_from_string_test() {
  assert poem_status.from_string("active") == Ok(poem_status.Active)
  assert poem_status.from_string("complete") == Ok(poem_status.Complete)
  assert poem_status.from_string("revealed") == Ok(poem_status.Revealed)
  assert poem_status.from_string("invalid") == Error(Nil)
}

pub fn extract_visible_hint_test() {
  let hint = poem.extract_visible_hint("the quick brown fox jumps", 3)
  assert hint == "brown fox jumps"
}

pub fn random_seed_line_returns_nonempty_test() {
  let seed = poem.random_seed_line()
  assert seed != ""
}

pub fn seed_lines_count_test() {
  assert list.length(poem.seed_lines()) == 12
}

pub fn allowed_line_counts_test() {
  let counts = poem.allowed_line_counts()
  assert list.length(counts) == 4
  assert list.contains(counts, 5)
  assert list.contains(counts, 7)
  assert list.contains(counts, 11)
  assert list.contains(counts, 13)
}

pub fn make_poem_line_test() {
  let poem_line = poem.make_poem_line("  the glass mountain whispered  ")
  assert poem_line.full_text == "the glass mountain whispered"
  assert poem_line.visible_hint == "glass mountain whispered"
}

pub fn generate_title_nonempty_test() {
  let lines = [
    poem.PoemLine(
      full_text: "the marble staircase dissolved into birdsong",
      visible_hint: "into birdsong",
    ),
    poem.PoemLine(
      full_text: "silver rivers carried forgotten melodies",
      visible_hint: "forgotten melodies",
    ),
  ]
  let title = poem.generate_title(lines)
  assert title != ""
  assert title != "Untitled Dream"
}

pub fn generate_title_empty_returns_fallback_test() {
  assert poem.generate_title([]) == "Untitled Dream"
}

pub fn capitalize_first_test() {
  assert poem.capitalize_first("moon") == "Moon"
  assert poem.capitalize_first("") == ""
}

pub fn surrealist_connectors_count_test() {
  assert list.length(poem.surrealist_connectors()) == 8
}

// --- Database repo tests ---

pub fn create_poem_inserts_record_test() {
  let connection = setup_test_db()
  let seed_line = "The exquisite corpse shall drink the new wine"
  let seed_hint = poem.extract_visible_hint(seed_line, 3)
  let assert Ok(created_poem) =
    poem_repo.create(connection, 11, seed_line, seed_hint)
  assert created_poem.total_lines == 11
  assert created_poem.seed_line == seed_line
  assert created_poem.status == poem_status.Active
  assert created_poem.version == 0
  assert string.length(created_poem.id) == 12
}

pub fn get_poem_by_id_test() {
  let connection = setup_test_db()
  let assert Ok(created_poem) =
    poem_repo.create(connection, 7, "test seed line", "seed line")
  let assert Ok(fetched_poem) =
    poem_repo.get_by_id(connection, created_poem.id)
  assert fetched_poem.id == created_poem.id
  assert fetched_poem.total_lines == 7
}

pub fn get_poem_not_found_test() {
  let connection = setup_test_db()
  let result = poem_repo.get_by_id(connection, "nonexistent_id")
  assert case result {
    Error(sqlight.SqlightError(sqlight.Notfound, _, _)) -> True
    _ -> False
  }
}

pub fn list_poems_test() {
  let connection = setup_test_db()
  let assert Ok(_) =
    poem_repo.create(connection, 5, "first seed", "first seed")
  let assert Ok(_) =
    poem_repo.create(connection, 7, "second seed", "second seed")
  let assert Ok(all_poems) =
    poem_repo.list(connection, option.None)
  assert list.length(all_poems) == 2
}

pub fn list_poems_with_status_filter_test() {
  let connection = setup_test_db()
  let assert Ok(poem_one) =
    poem_repo.create(connection, 5, "first seed", "first seed")
  let assert Ok(_) =
    poem_repo.create(connection, 7, "second seed", "second seed")
  // Mark one as complete
  let assert Ok(_) =
    poem_repo.update_status(connection, poem_one.id, poem_status.Complete)
  let assert Ok(active_poems) =
    poem_repo.list(connection, option.Some("active"))
  assert list.length(active_poems) == 1
  let assert Ok(complete_poems) =
    poem_repo.list(connection, option.Some("complete"))
  assert list.length(complete_poems) == 1
}

pub fn increment_version_test() {
  let connection = setup_test_db()
  let assert Ok(created_poem) =
    poem_repo.create(connection, 11, "test seed", "seed")
  assert created_poem.version == 0
  let assert Ok(_) =
    poem_repo.increment_version(connection, created_poem.id, 0)
  let assert Ok(updated_poem) =
    poem_repo.get_by_id(connection, created_poem.id)
  assert updated_poem.version == 1
}

pub fn increment_version_conflict_test() {
  let connection = setup_test_db()
  let assert Ok(created_poem) =
    poem_repo.create(connection, 11, "test seed", "seed")
  // Try to increment with wrong version
  let result = poem_repo.increment_version(connection, created_poem.id, 99)
  assert case result {
    Error(sqlight.SqlightError(sqlight.Busy, _, _)) -> True
    _ -> False
  }
}

pub fn add_poem_line_test() {
  let connection = setup_test_db()
  let assert Ok(created_poem) =
    poem_repo.create(connection, 11, "test seed", "seed")
  let assert Ok(added_line) =
    poem_line_repo.add_line(
      connection,
      created_poem.id,
      2,
      "a velvet dream unfolds",
      "dream unfolds",
    )
  assert added_line.line_number == 2
  assert added_line.full_text == "a velvet dream unfolds"
  assert added_line.visible_hint == "dream unfolds"
}

pub fn get_lines_for_poem_test() {
  let connection = setup_test_db()
  let assert Ok(created_poem) =
    poem_repo.create(connection, 11, "test seed", "seed")
  let assert Ok(_) =
    poem_line_repo.add_line(
      connection,
      created_poem.id,
      2,
      "second line",
      "second line",
    )
  let assert Ok(all_lines) =
    poem_line_repo.get_lines_for_poem(connection, created_poem.id)
  // Seed line (1) + added line (2) = 2
  assert list.length(all_lines) == 2
  let assert Ok(first_line) = list.first(all_lines)
  assert first_line.line_number == 1
}

pub fn count_lines_test() {
  let connection = setup_test_db()
  let assert Ok(created_poem) =
    poem_repo.create(connection, 11, "test seed", "seed")
  let assert Ok(initial_count) =
    poem_line_repo.count_lines(connection, created_poem.id)
  assert initial_count == 1
  let assert Ok(_) =
    poem_line_repo.add_line(connection, created_poem.id, 2, "line 2", "line 2")
  let assert Ok(updated_count) =
    poem_line_repo.count_lines(connection, created_poem.id)
  assert updated_count == 2
}

pub fn update_poem_status_test() {
  let connection = setup_test_db()
  let assert Ok(created_poem) =
    poem_repo.create(connection, 11, "test seed", "seed")
  let assert Ok(_) =
    poem_repo.update_status(connection, created_poem.id, poem_status.Complete)
  let assert Ok(updated_poem) =
    poem_repo.get_by_id(connection, created_poem.id)
  assert updated_poem.status == poem_status.Complete
}

pub fn set_poem_title_test() {
  let connection = setup_test_db()
  let assert Ok(created_poem) =
    poem_repo.create(connection, 11, "test seed", "seed")
  let assert Ok(_) =
    poem_repo.set_title(connection, created_poem.id, "Moon beneath Waters")
  let assert Ok(updated_poem) =
    poem_repo.get_by_id(connection, created_poem.id)
  assert updated_poem.title == "Moon beneath Waters"
}

// --- HTTP handler tests ---

pub fn create_poem_endpoint_test() {
  let connection = setup_test_db()
  let ctx = test_context(connection)
  let request_body = json.object([#("total_lines", json.int(7))])
  let response =
    simulate.request(http.Post, "/api/poems")
    |> simulate.json_body(request_body)
    |> handle_request(ctx)
  assert response.status == 201
  let body = simulate.read_body(response)
  assert string.contains(body, "\"total_lines\":7")
  assert string.contains(body, "\"status\":\"active\"")
}

pub fn create_poem_default_line_count_test() {
  let connection = setup_test_db()
  let ctx = test_context(connection)
  let request_body = json.object([])
  let response =
    simulate.request(http.Post, "/api/poems")
    |> simulate.json_body(request_body)
    |> handle_request(ctx)
  assert response.status == 201
  let body = simulate.read_body(response)
  assert string.contains(body, "\"total_lines\":11")
}

pub fn create_poem_invalid_line_count_test() {
  let connection = setup_test_db()
  let ctx = test_context(connection)
  let request_body = json.object([#("total_lines", json.int(3))])
  let response =
    simulate.request(http.Post, "/api/poems")
    |> simulate.json_body(request_body)
    |> handle_request(ctx)
  assert response.status == 400
}

pub fn list_poems_endpoint_test() {
  let connection = setup_test_db()
  let ctx = test_context(connection)
  // Create a poem first
  let create_body = json.object([#("total_lines", json.int(5))])
  let _ =
    simulate.request(http.Post, "/api/poems")
    |> simulate.json_body(create_body)
    |> handle_request(ctx)
  // List poems
  let response =
    simulate.request(http.Get, "/api/poems")
    |> handle_request(ctx)
  assert response.status == 200
  let body = simulate.read_body(response)
  assert string.contains(body, "\"poems\":")
}

pub fn list_poems_with_status_filter_endpoint_test() {
  let connection = setup_test_db()
  let ctx = test_context(connection)
  // Create a poem
  let create_body = json.object([#("total_lines", json.int(5))])
  let _ =
    simulate.request(http.Post, "/api/poems")
    |> simulate.json_body(create_body)
    |> handle_request(ctx)
  // List only active poems
  let response =
    simulate.request(http.Get, "/api/poems?status=active")
    |> handle_request(ctx)
  assert response.status == 200
}

pub fn get_poem_endpoint_test() {
  let connection = setup_test_db()
  let ctx = test_context(connection)
  // Create a poem
  let assert Ok(created_poem) =
    poem_repo.create(connection, 7, "test seed line", "seed line")
  // Fetch it via API
  let response =
    simulate.request(http.Get, "/api/poems/" <> created_poem.id)
    |> handle_request(ctx)
  assert response.status == 200
  let body = simulate.read_body(response)
  assert string.contains(body, created_poem.id)
  assert string.contains(body, "\"total_lines\":7")
}

pub fn get_poem_not_found_endpoint_test() {
  let connection = setup_test_db()
  let ctx = test_context(connection)
  let response =
    simulate.request(http.Get, "/api/poems/nonexistent12")
    |> handle_request(ctx)
  assert response.status == 404
}

pub fn add_line_endpoint_test() {
  let connection = setup_test_db()
  let ctx = test_context(connection)
  let assert Ok(created_poem) =
    poem_repo.create(connection, 7, "test seed line", "seed line")
  let line_body =
    json.object([
      #("text", json.string("a velvet dream unfolds gently")),
      #("version", json.int(0)),
    ])
  let response =
    simulate.request(http.Post, "/api/poems/" <> created_poem.id <> "/lines")
    |> simulate.json_body(line_body)
    |> handle_request(ctx)
  assert response.status == 201
  let body = simulate.read_body(response)
  assert string.contains(body, "\"line_number\":2")
  assert string.contains(body, "\"version\":1")
}

pub fn add_line_empty_text_rejected_test() {
  let connection = setup_test_db()
  let ctx = test_context(connection)
  let assert Ok(created_poem) =
    poem_repo.create(connection, 7, "test seed line", "seed line")
  let line_body =
    json.object([#("text", json.string("   ")), #("version", json.int(0))])
  let response =
    simulate.request(http.Post, "/api/poems/" <> created_poem.id <> "/lines")
    |> simulate.json_body(line_body)
    |> handle_request(ctx)
  assert response.status == 400
}

pub fn add_line_version_conflict_test() {
  let connection = setup_test_db()
  let ctx = test_context(connection)
  let assert Ok(created_poem) =
    poem_repo.create(connection, 7, "test seed line", "seed line")
  let line_body =
    json.object([
      #("text", json.string("a new line")),
      #("version", json.int(99)),
    ])
  let response =
    simulate.request(http.Post, "/api/poems/" <> created_poem.id <> "/lines")
    |> simulate.json_body(line_body)
    |> handle_request(ctx)
  assert response.status == 409
}

pub fn add_line_completes_poem_test() {
  let connection = setup_test_db()
  let ctx = test_context(connection)
  // Create a 5-line poem (seed counts as line 1)
  let assert Ok(created_poem) =
    poem_repo.create(connection, 5, "test seed line", "seed line")
  // Add lines 2-5 to complete the poem
  let assert Ok(_) =
    poem_line_repo.add_line(connection, created_poem.id, 2, "line two", "line two")
  let assert Ok(_) =
    poem_line_repo.add_line(connection, created_poem.id, 3, "line three", "line three")
  let assert Ok(_) =
    poem_line_repo.add_line(connection, created_poem.id, 4, "line four", "line four")
  // Increment version to match
  let assert Ok(_) =
    poem_repo.increment_version(connection, created_poem.id, 0)
  let assert Ok(_) =
    poem_repo.increment_version(connection, created_poem.id, 1)
  let assert Ok(_) =
    poem_repo.increment_version(connection, created_poem.id, 2)
  // Add the final line via API
  let line_body =
    json.object([
      #("text", json.string("the final line")),
      #("version", json.int(3)),
    ])
  let response =
    simulate.request(http.Post, "/api/poems/" <> created_poem.id <> "/lines")
    |> simulate.json_body(line_body)
    |> handle_request(ctx)
  assert response.status == 201
  let body = simulate.read_body(response)
  assert string.contains(body, "\"is_complete\":true")
}

pub fn reveal_poem_endpoint_test() {
  let connection = setup_test_db()
  let ctx = test_context(connection)
  let assert Ok(created_poem) =
    poem_repo.create(connection, 5, "test seed line", "seed line")
  // Add 4 more lines to complete
  let assert Ok(_) =
    poem_line_repo.add_line(connection, created_poem.id, 2, "second line words", "line words")
  let assert Ok(_) =
    poem_line_repo.add_line(connection, created_poem.id, 3, "third line words", "line words")
  let assert Ok(_) =
    poem_line_repo.add_line(connection, created_poem.id, 4, "fourth line words", "line words")
  let assert Ok(_) =
    poem_line_repo.add_line(connection, created_poem.id, 5, "fifth line words", "line words")
  // Mark poem as complete
  let assert Ok(_) =
    poem_repo.update_status(connection, created_poem.id, poem_status.Complete)
  // Reveal via API
  let response =
    simulate.request(http.Post, "/api/poems/" <> created_poem.id <> "/reveal")
    |> handle_request(ctx)
  assert response.status == 200
  let body = simulate.read_body(response)
  assert string.contains(body, "\"status\":\"revealed\"")
  assert string.contains(body, "\"title\":")
  assert string.contains(body, "\"full_text\":")
}

pub fn reveal_active_poem_rejected_test() {
  let connection = setup_test_db()
  let ctx = test_context(connection)
  let assert Ok(created_poem) =
    poem_repo.create(connection, 5, "test seed line", "seed line")
  let response =
    simulate.request(http.Post, "/api/poems/" <> created_poem.id <> "/reveal")
    |> handle_request(ctx)
  assert response.status == 400
}

pub fn reveal_already_revealed_returns_current_state_test() {
  let connection = setup_test_db()
  let ctx = test_context(connection)
  let assert Ok(created_poem) =
    poem_repo.create(connection, 5, "test seed line", "seed line")
  let assert Ok(_) =
    poem_repo.update_status(connection, created_poem.id, poem_status.Revealed)
  let assert Ok(_) =
    poem_repo.set_title(connection, created_poem.id, "Existing Title")
  let response =
    simulate.request(http.Post, "/api/poems/" <> created_poem.id <> "/reveal")
    |> handle_request(ctx)
  assert response.status == 200
  let body = simulate.read_body(response)
  assert string.contains(body, "\"title\":\"Existing Title\"")
}

pub fn method_not_allowed_test() {
  let connection = setup_test_db()
  let ctx = test_context(connection)
  let response =
    simulate.request(http.Delete, "/api/poems")
    |> handle_request(ctx)
  assert response.status == 405
}

// --- Migration test ---

pub fn migration_runs_idempotently_test() {
  let connection = setup_test_db()
  // Running migration again should succeed (IF NOT EXISTS)
  let assert Ok(_) = migration.run(connection)
}

// --- Database initialization test ---

pub fn database_initialize_test() {
  let assert Ok(connection) = database.initialize(":memory:")
  // Should be able to query the poems table
  let assert Ok(poems) =
    poem_repo.list(connection, option.None)
  assert poems == []
}
