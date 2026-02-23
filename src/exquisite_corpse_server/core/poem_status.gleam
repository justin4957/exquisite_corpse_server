/// Status lifecycle for a poem: active → complete → revealed.
import gleam/dynamic/decode

pub type PoemStatus {
  Active
  Complete
  Revealed
}

/// Converts a PoemStatus to its database string representation.
pub fn to_string(status: PoemStatus) -> String {
  case status {
    Active -> "active"
    Complete -> "complete"
    Revealed -> "revealed"
  }
}

/// Parses a database string into a PoemStatus.
pub fn from_string(status_string: String) -> Result(PoemStatus, Nil) {
  case status_string {
    "active" -> Ok(Active)
    "complete" -> Ok(Complete)
    "revealed" -> Ok(Revealed)
    _ -> Error(Nil)
  }
}

/// Decoder for reading a PoemStatus from a database row.
pub fn decoder() -> decode.Decoder(PoemStatus) {
  use status_string <- decode.then(decode.string)
  case from_string(status_string) {
    Ok(status) -> decode.success(status)
    Error(_) -> decode.failure(Active, "PoemStatus")
  }
}
