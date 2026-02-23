/// HTTP handlers for poem API endpoints.
import exquisite_corpse_server/core/poem
import exquisite_corpse_server/core/poem_status
import exquisite_corpse_server/data/poem_line_repo
import exquisite_corpse_server/data/poem_repo
import exquisite_corpse_server/web/api_error
import exquisite_corpse_server/web/context.{type Context}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/string
import sqlight
import wisp

/// POST /api/poems — Create a new poem.
pub fn create_poem(request: wisp.Request, ctx: Context) -> wisp.Response {
  use json_body <- wisp.require_json(request)

  let total_lines_decoder = {
    use total_lines <- decode.optional_field(
      "total_lines",
      poem.default_line_count,
      decode.int,
    )
    decode.success(total_lines)
  }

  case decode.run(json_body, total_lines_decoder) {
    Ok(total_lines) -> {
      let valid_counts = poem.allowed_line_counts()
      case list.contains(valid_counts, total_lines) {
        False ->
          api_error.bad_request(
            "total_lines must be one of: "
            <> list.map(valid_counts, int.to_string)
            |> string.join(", "),
          )
        True -> {
          let seed_line = poem.random_seed_line()
          let seed_poem_line = poem.make_poem_line(seed_line)
          case
            poem_repo.create(
              ctx.db_connection,
              total_lines,
              seed_poem_line.full_text,
              seed_poem_line.visible_hint,
            )
          {
            Ok(created_poem) -> {
              // Return poem with seed line info
              let response_json =
                json.object([
                  #("id", json.string(created_poem.id)),
                  #("total_lines", json.int(created_poem.total_lines)),
                  #(
                    "status",
                    json.string(poem_status.to_string(created_poem.status)),
                  ),
                  #("seed_line", json.string(created_poem.seed_line)),
                  #("visible_hint", json.string(seed_poem_line.visible_hint)),
                  #("version", json.int(created_poem.version)),
                  #("created_at", json.string(created_poem.created_at)),
                ])
                |> json.to_string
              wisp.json_response(response_json, 201)
            }
            Error(sqlight_error) ->
              api_error.from_database_error(sqlight_error.message)
          }
        }
      }
    }
    Error(_) -> api_error.bad_request("Invalid request body")
  }
}

/// GET /api/poems — List poems with optional status filter.
pub fn list_poems(request: wisp.Request, ctx: Context) -> wisp.Response {
  let query_params = wisp.get_query(request)
  let status_filter =
    list.key_find(query_params, "status")
    |> option.from_result

  case poem_repo.list(ctx.db_connection, status_filter) {
    Ok(poem_summaries) -> {
      let response_json =
        json.object([
          #(
            "poems",
            json.array(poem_summaries, fn(summary) {
              json.object([
                #("id", json.string(summary.id)),
                #("total_lines", json.int(summary.total_lines)),
                #("current_line_count", json.int(summary.current_line_count)),
                #("status", json.string(summary.status)),
                #("seed_line", json.string(summary.seed_line)),
                #("created_at", json.string(summary.created_at)),
              ])
            }),
          ),
        ])
        |> json.to_string
      wisp.json_response(response_json, 200)
    }
    Error(sqlight_error) -> api_error.from_database_error(sqlight_error.message)
  }
}

/// GET /api/poems/:id — Fetch a single poem.
pub fn get_poem(ctx: Context, poem_id: String) -> wisp.Response {
  case poem_repo.get_by_id(ctx.db_connection, poem_id) {
    Ok(found_poem) -> {
      case poem_line_repo.get_lines_for_poem(ctx.db_connection, poem_id) {
        Ok(poem_lines) -> {
          let is_revealed = found_poem.status == poem_status.Revealed
          let lines_json =
            json.array(poem_lines, fn(line) {
              case is_revealed {
                True ->
                  json.object([
                    #("line_number", json.int(line.line_number)),
                    #("full_text", json.string(line.full_text)),
                    #("visible_hint", json.string(line.visible_hint)),
                  ])
                False ->
                  json.object([
                    #("line_number", json.int(line.line_number)),
                    #("visible_hint", json.string(line.visible_hint)),
                  ])
              }
            })
          let response_json =
            json.object([
              #("id", json.string(found_poem.id)),
              #("total_lines", json.int(found_poem.total_lines)),
              #("status", json.string(poem_status.to_string(found_poem.status))),
              #("title", json.string(found_poem.title)),
              #("seed_line", json.string(found_poem.seed_line)),
              #("version", json.int(found_poem.version)),
              #("current_line_count", json.int(list.length(poem_lines))),
              #("lines", lines_json),
              #("created_at", json.string(found_poem.created_at)),
              #("updated_at", json.string(found_poem.updated_at)),
            ])
            |> json.to_string
          wisp.json_response(response_json, 200)
        }
        Error(sqlight_error) ->
          api_error.from_database_error(sqlight_error.message)
      }
    }
    Error(sqlight.SqlightError(sqlight.Notfound, _, _)) ->
      api_error.not_found("Poem not found")
    Error(sqlight_error) -> api_error.from_database_error(sqlight_error.message)
  }
}

/// POST /api/poems/:id/lines — Add a line to a poem.
pub fn add_line(
  request: wisp.Request,
  ctx: Context,
  poem_id: String,
) -> wisp.Response {
  use json_body <- wisp.require_json(request)

  let line_body_decoder = {
    use text <- decode.field("text", decode.string)
    use version <- decode.field("version", decode.int)
    decode.success(#(text, version))
  }

  case decode.run(json_body, line_body_decoder) {
    Ok(#(raw_text, expected_version)) -> {
      let trimmed_text = string.trim(raw_text)
      case trimmed_text {
        "" -> api_error.bad_request("Line text cannot be empty")
        valid_text -> {
          // Fetch the poem first to validate state
          case poem_repo.get_by_id(ctx.db_connection, poem_id) {
            Ok(found_poem) -> {
              case found_poem.status {
                poem_status.Active -> {
                  // Try optimistic locking
                  case
                    poem_repo.increment_version(
                      ctx.db_connection,
                      poem_id,
                      expected_version,
                    )
                  {
                    Ok(_) -> {
                      // Determine line number
                      case
                        poem_line_repo.count_lines(ctx.db_connection, poem_id)
                      {
                        Ok(current_count) -> {
                          let next_line_number = current_count + 1
                          let new_poem_line = poem.make_poem_line(valid_text)
                          case
                            poem_line_repo.add_line(
                              ctx.db_connection,
                              poem_id,
                              next_line_number,
                              new_poem_line.full_text,
                              new_poem_line.visible_hint,
                            )
                          {
                            Ok(inserted_line) -> {
                              // Check if poem is now complete
                              let is_complete =
                                next_line_number >= found_poem.total_lines
                              case is_complete {
                                True -> {
                                  let _ =
                                    poem_repo.update_status(
                                      ctx.db_connection,
                                      poem_id,
                                      poem_status.Complete,
                                    )
                                  Nil
                                }
                                False -> Nil
                              }
                              let new_version = expected_version + 1
                              let response_json =
                                json.object([
                                  #(
                                    "line_number",
                                    json.int(inserted_line.line_number),
                                  ),
                                  #(
                                    "full_text",
                                    json.string(inserted_line.full_text),
                                  ),
                                  #(
                                    "visible_hint",
                                    json.string(inserted_line.visible_hint),
                                  ),
                                  #("version", json.int(new_version)),
                                  #("is_complete", json.bool(is_complete)),
                                ])
                                |> json.to_string
                              wisp.json_response(response_json, 201)
                            }
                            Error(sqlight_error) ->
                              api_error.from_database_error(
                                sqlight_error.message,
                              )
                          }
                        }
                        Error(sqlight_error) ->
                          api_error.from_database_error(sqlight_error.message)
                      }
                    }
                    Error(sqlight.SqlightError(sqlight.Busy, _, _)) ->
                      api_error.conflict(
                        "Version conflict: poem has been modified by another contributor",
                      )
                    Error(sqlight_error) ->
                      api_error.from_database_error(sqlight_error.message)
                  }
                }
                poem_status.Complete ->
                  api_error.bad_request("Poem is already complete")
                poem_status.Revealed ->
                  api_error.bad_request("Poem has already been revealed")
              }
            }
            Error(sqlight.SqlightError(sqlight.Notfound, _, _)) ->
              api_error.not_found("Poem not found")
            Error(sqlight_error) ->
              api_error.from_database_error(sqlight_error.message)
          }
        }
      }
    }
    Error(_) ->
      api_error.bad_request(
        "Invalid request body: requires 'text' and 'version' fields",
      )
  }
}

/// POST /api/poems/:id/reveal — Reveal a completed poem.
pub fn reveal_poem(ctx: Context, poem_id: String) -> wisp.Response {
  case poem_repo.get_by_id(ctx.db_connection, poem_id) {
    Ok(found_poem) -> {
      case found_poem.status {
        poem_status.Complete -> {
          // Get all lines to generate title
          case poem_line_repo.get_lines_for_poem(ctx.db_connection, poem_id) {
            Ok(poem_lines) -> {
              let domain_lines =
                list.map(poem_lines, fn(line_record) {
                  poem.PoemLine(
                    full_text: line_record.full_text,
                    visible_hint: line_record.visible_hint,
                  )
                })
              let generated_title = poem.generate_title(domain_lines)

              // Update status and title
              case
                poem_repo.update_status(
                  ctx.db_connection,
                  poem_id,
                  poem_status.Revealed,
                )
              {
                Ok(_) -> {
                  let _ =
                    poem_repo.set_title(
                      ctx.db_connection,
                      poem_id,
                      generated_title,
                    )
                  let lines_json =
                    json.array(poem_lines, fn(line) {
                      json.object([
                        #("line_number", json.int(line.line_number)),
                        #("full_text", json.string(line.full_text)),
                        #("visible_hint", json.string(line.visible_hint)),
                      ])
                    })
                  let response_json =
                    json.object([
                      #("id", json.string(found_poem.id)),
                      #("title", json.string(generated_title)),
                      #("status", json.string("revealed")),
                      #("lines", lines_json),
                    ])
                    |> json.to_string
                  wisp.json_response(response_json, 200)
                }
                Error(sqlight_error) ->
                  api_error.from_database_error(sqlight_error.message)
              }
            }
            Error(sqlight_error) ->
              api_error.from_database_error(sqlight_error.message)
          }
        }
        poem_status.Revealed -> {
          // Already revealed — return current state
          case poem_line_repo.get_lines_for_poem(ctx.db_connection, poem_id) {
            Ok(poem_lines) -> {
              let lines_json =
                json.array(poem_lines, fn(line) {
                  json.object([
                    #("line_number", json.int(line.line_number)),
                    #("full_text", json.string(line.full_text)),
                    #("visible_hint", json.string(line.visible_hint)),
                  ])
                })
              let response_json =
                json.object([
                  #("id", json.string(found_poem.id)),
                  #("title", json.string(found_poem.title)),
                  #("status", json.string("revealed")),
                  #("lines", lines_json),
                ])
                |> json.to_string
              wisp.json_response(response_json, 200)
            }
            Error(sqlight_error) ->
              api_error.from_database_error(sqlight_error.message)
          }
        }
        poem_status.Active -> api_error.bad_request("Poem is not yet complete")
      }
    }
    Error(sqlight.SqlightError(sqlight.Notfound, _, _)) ->
      api_error.not_found("Poem not found")
    Error(sqlight_error) -> api_error.from_database_error(sqlight_error.message)
  }
}
