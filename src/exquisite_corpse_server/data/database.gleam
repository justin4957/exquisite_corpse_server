/// Database connection management and initialization.
import exquisite_corpse_server/data/migration
import sqlight

/// Opens a SQLite connection and runs migrations.
pub fn initialize(database_path: String) -> Result(sqlight.Connection, String) {
  case sqlight.open(database_path) {
    Ok(connection) -> {
      // Enable WAL mode for better concurrent read performance
      case sqlight.exec("PRAGMA journal_mode=WAL;", on: connection) {
        Ok(_) -> Nil
        Error(_) -> Nil
      }
      // Enable foreign key enforcement
      case sqlight.exec("PRAGMA foreign_keys=ON;", on: connection) {
        Ok(_) -> Nil
        Error(_) -> Nil
      }
      case migration.run(connection) {
        Ok(_) -> Ok(connection)
        Error(sqlight_error) -> Error(sqlight_error.message)
      }
    }
    Error(sqlight_error) -> Error(sqlight_error.message)
  }
}
