/// Exquisite Corpse poetry game HTTP API server.
import envoy
import exquisite_corpse_server/data/database
import exquisite_corpse_server/web/context.{Context}
import exquisite_corpse_server/web/middleware
import exquisite_corpse_server/web/router
import gleam/erlang/process
import gleam/int
import gleam/io
import mist
import wisp
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()

  let port = case envoy.get("PORT") {
    Ok(port_string) ->
      case int.parse(port_string) {
        Ok(port_number) -> port_number
        Error(_) -> 8080
      }
    Error(_) -> 8080
  }

  let database_path = case envoy.get("DATABASE_PATH") {
    Ok(path) -> path
    Error(_) -> "exquisite_corpse.db"
  }

  let static_directory = case envoy.get("STATIC_DIR") {
    Ok(dir) -> dir
    Error(_) -> "priv/static"
  }

  let secret_key_base = case envoy.get("SECRET_KEY_BASE") {
    Ok(secret) -> secret
    Error(_) -> wisp.random_string(64)
  }

  // Initialize database
  let assert Ok(db_connection) = database.initialize(database_path)
  let ctx =
    Context(db_connection: db_connection, static_directory: static_directory)

  // Create request handler with middleware
  let handler = fn(request) {
    middleware.apply(request, ctx, fn(req) { router.handle_request(req, ctx) })
  }

  let assert Ok(_) =
    handler
    |> wisp_mist.handler(secret_key_base)
    |> mist.new
    |> mist.port(port)
    |> mist.start

  io.println(
    "Exquisite Corpse server running on http://localhost:"
    <> int.to_string(port),
  )
  process.sleep_forever()
}
