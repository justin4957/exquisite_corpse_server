/// Structured JSON error responses for the API.
import gleam/json
import wisp

/// Returns a JSON error response with the given status code and message.
pub fn json_error(status: Int, message: String) -> wisp.Response {
  let error_body =
    json.object([#("error", json.string(message))])
    |> json.to_string

  wisp.json_response(error_body, status)
}

/// 400 Bad Request with a message.
pub fn bad_request(message: String) -> wisp.Response {
  json_error(400, message)
}

/// 404 Not Found with a message.
pub fn not_found(message: String) -> wisp.Response {
  json_error(404, message)
}

/// 409 Conflict with a message.
pub fn conflict(message: String) -> wisp.Response {
  json_error(409, message)
}

/// 422 Unprocessable Entity with a message.
pub fn unprocessable_entity(message: String) -> wisp.Response {
  json_error(422, message)
}

/// 500 Internal Server Error with a message.
pub fn internal_error(message: String) -> wisp.Response {
  json_error(500, message)
}

/// Converts a generic error string into a 500 response.
pub fn from_database_error(error_message: String) -> wisp.Response {
  internal_error("Database error: " <> error_message)
}
