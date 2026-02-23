/// Request context carrying shared dependencies.
import sqlight

pub type Context {
  Context(db_connection: sqlight.Connection, static_directory: String)
}
