/// CORS header helpers for cross-origin requests during development.
import gleam/http
import wisp

/// Adds CORS headers to a response.
pub fn add_headers(response: wisp.Response) -> wisp.Response {
  response
  |> wisp.set_header("access-control-allow-origin", "*")
  |> wisp.set_header("access-control-allow-methods", "GET, POST, OPTIONS")
  |> wisp.set_header("access-control-allow-headers", "content-type")
  |> wisp.set_header("access-control-max-age", "86400")
}

/// Handles preflight OPTIONS requests with appropriate CORS headers.
pub fn handle_preflight(request: wisp.Request) -> Result(wisp.Response, Nil) {
  case request.method {
    http.Options ->
      Ok(
        wisp.response(204)
        |> add_headers,
      )
    _ -> Error(Nil)
  }
}
