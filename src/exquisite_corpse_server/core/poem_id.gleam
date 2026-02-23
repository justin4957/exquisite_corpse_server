/// Opaque poem ID type with cryptographically random generation.
import gleam/bit_array
import gleam/string

pub opaque type PoemId {
  PoemId(value: String)
}

/// Generates a new random poem ID using :crypto.strong_rand_bytes.
/// Produces a 12-character URL-safe alphanumeric string.
pub fn generate() -> PoemId {
  let random_bytes = strong_rand_bytes(9)
  let encoded =
    bit_array.base64_url_encode(random_bytes, False)
    |> string.slice(0, 12)
  PoemId(encoded)
}

/// Creates a PoemId from an existing string value (e.g., from database).
pub fn from_string(value: String) -> PoemId {
  PoemId(value)
}

/// Extracts the string value from a PoemId.
pub fn to_string(poem_id: PoemId) -> String {
  poem_id.value
}

@external(erlang, "crypto", "strong_rand_bytes")
fn strong_rand_bytes(count: Int) -> BitArray
