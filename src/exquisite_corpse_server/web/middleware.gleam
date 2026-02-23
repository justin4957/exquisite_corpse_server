/// Middleware stack for request processing.
import exquisite_corpse_server/web/context.{type Context}
import exquisite_corpse_server/web/cors
import wisp

/// Applies the standard middleware stack to a request handler.
pub fn apply(
  request: wisp.Request,
  ctx: Context,
  handler: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  let request = wisp.method_override(request)
  use <- wisp.log_request(request)
  use <- wisp.rescue_crashes
  use request <- wisp.handle_head(request)
  use <- wisp.serve_static(
    request,
    under: "/static",
    from: ctx.static_directory,
  )

  // Handle CORS preflight
  case cors.handle_preflight(request) {
    Ok(preflight_response) -> preflight_response
    Error(_) -> {
      let response = handler(request)
      cors.add_headers(response)
    }
  }
}
