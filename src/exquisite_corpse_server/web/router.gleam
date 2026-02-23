/// Route dispatch for the exquisite corpse API and SPA fallback.
import exquisite_corpse_server/web/context.{type Context}
import exquisite_corpse_server/web/poem_handler
import gleam/http
import gleam/option
import simplifile
import wisp

/// Dispatches requests to the appropriate handler.
pub fn handle_request(request: wisp.Request, ctx: Context) -> wisp.Response {
  case wisp.path_segments(request) {
    // API routes
    ["api", "poems"] ->
      case request.method {
        http.Post -> poem_handler.create_poem(request, ctx)
        http.Get -> poem_handler.list_poems(request, ctx)
        _ -> wisp.method_not_allowed(allowed: [http.Get, http.Post])
      }

    ["api", "poems", poem_id] ->
      case request.method {
        http.Get -> poem_handler.get_poem(ctx, poem_id)
        _ -> wisp.method_not_allowed(allowed: [http.Get])
      }

    ["api", "poems", poem_id, "lines"] ->
      case request.method {
        http.Post -> poem_handler.add_line(request, ctx, poem_id)
        _ -> wisp.method_not_allowed(allowed: [http.Post])
      }

    ["api", "poems", poem_id, "reveal"] ->
      case request.method {
        http.Post -> poem_handler.reveal_poem(ctx, poem_id)
        _ -> wisp.method_not_allowed(allowed: [http.Post])
      }

    // SPA fallback: serve index.html for non-API routes
    _ -> serve_spa_fallback(ctx)
  }
}

/// Serves index.html for SPA client-side routing.
fn serve_spa_fallback(ctx: Context) -> wisp.Response {
  let index_path = ctx.static_directory <> "/index.html"
  case simplifile.is_file(index_path) {
    Ok(True) ->
      wisp.response(200)
      |> wisp.set_header("content-type", "text/html; charset=utf-8")
      |> wisp.set_body(wisp.File(
        path: index_path,
        offset: 0,
        limit: option.None,
      ))
    _ -> wisp.not_found()
  }
}
