/// Pure utilities for poem construction and seed line selection.
/// Ported from the client-side poem.gleam for server-side use on BEAM.
import gleam/list
import gleam/string

/// The default number of lines in a completed poem.
pub const default_line_count = 11

/// Returns the allowed line count options for a poem.
pub fn allowed_line_counts() -> List(Int) {
  [5, 7, 11, 13]
}

/// Default number of words to show as a hint to the next writer.
pub const default_hint_word_count = 3

/// A single line of the poem with full text and visible hint.
pub type PoemLine {
  PoemLine(full_text: String, visible_hint: String)
}

/// Curated surrealist opening lines to seed each poem.
pub fn seed_lines() -> List(String) {
  [
    "The exquisite corpse shall drink the new wine",
    "Under the velvet moon the shadows learned to sing",
    "A clockwork sparrow nested in the dictionary",
    "The marble staircase dissolved into birdsong",
    "Seven telegrams arrived from the future yesterday",
    "The porcelain whale swam through the chandelier",
    "Forgotten alphabets bloomed in the empty theater",
    "The glass mountain whispered its oldest recipe",
    "A silk umbrella opened inside the volcano",
    "The mechanical garden grew wild with equations",
    "Twelve violins played the color of Thursday",
    "The paper compass pointed toward a dream",
  ]
}

/// Picks a random seed line from the curated list.
pub fn random_seed_line() -> String {
  let lines = seed_lines()
  let line_count = list.length(lines)
  let random_index = rand_uniform(line_count) - 1
  case list.drop(lines, random_index) {
    [selected, ..] -> selected
    [] -> "The exquisite corpse shall drink the new wine"
  }
}

/// Extracts the last `word_count` words from a line as a visible hint.
/// If the line has fewer words than `word_count`, returns the full line.
pub fn extract_visible_hint(line: String, word_count: Int) -> String {
  let trimmed = string.trim(line)
  let words = string.split(trimmed, " ")
  let filtered_words = list.filter(words, fn(word) { word != "" })
  let total_words = list.length(filtered_words)
  case total_words <= word_count {
    True -> string.join(filtered_words, " ")
    False -> {
      filtered_words
      |> list.drop(total_words - word_count)
      |> string.join(" ")
    }
  }
}

/// Formats all poem lines into a single string, joining full_text with newlines.
pub fn format_poem_text(lines: List(PoemLine)) -> String {
  lines
  |> list.map(fn(poem_line) { poem_line.full_text })
  |> string.join("\n")
}

/// Constructs a PoemLine with pre-computed hint from the given text.
pub fn make_poem_line(text: String) -> PoemLine {
  let trimmed = string.trim(text)
  let hint = extract_visible_hint(trimmed, default_hint_word_count)
  PoemLine(full_text: trimmed, visible_hint: hint)
}

/// Minimum word length to qualify as a title keyword.
const minimum_title_word_length = 3

/// Surrealist connector phrases for joining title words.
pub fn surrealist_connectors() -> List(String) {
  [
    "of the", "beneath", "against", "within the", "and the", "beyond",
    "through the", "among the",
  ]
}

/// Generates a surrealist title from the first and last lines of the poem.
pub fn generate_title(lines: List(PoemLine)) -> String {
  let fallback_title = "Untitled Dream"
  case lines {
    [] -> fallback_title
    [single_line] -> {
      let significant_words = extract_significant_words(single_line.full_text)
      case list.length(significant_words) >= 2 {
        True -> build_title_from_words(significant_words, significant_words)
        False -> fallback_title
      }
    }
    [first_line, ..rest] -> {
      let last_line = case list.last(rest) {
        Ok(found_line) -> found_line
        Error(_) -> first_line
      }
      let first_words = extract_significant_words(first_line.full_text)
      let last_words = extract_significant_words(last_line.full_text)
      case list.is_empty(first_words) || list.is_empty(last_words) {
        True -> fallback_title
        False -> build_title_from_words(first_words, last_words)
      }
    }
  }
}

/// Extracts words with length >= minimum_title_word_length from a line.
fn extract_significant_words(line_text: String) -> List(String) {
  line_text
  |> string.trim
  |> string.split(" ")
  |> list.filter(fn(word) { string.length(word) >= minimum_title_word_length })
}

/// Builds a title by picking random words from two word lists
/// and joining them with a random surrealist connector.
fn build_title_from_words(
  first_words: List(String),
  last_words: List(String),
) -> String {
  let chosen_first = pick_random_element(first_words, "Dream")
  let chosen_last = pick_random_element(last_words, "Vision")
  let connectors = surrealist_connectors()
  let chosen_connector = pick_random_element(connectors, "beneath")
  capitalize_first(chosen_first)
  <> " "
  <> chosen_connector
  <> " "
  <> capitalize_first(chosen_last)
}

/// Picks a random element from a list, returning a fallback if the list is empty.
fn pick_random_element(items: List(String), fallback: String) -> String {
  let item_count = list.length(items)
  case item_count {
    0 -> fallback
    _ -> {
      let random_index = rand_uniform(item_count) - 1
      case list.drop(items, random_index) {
        [selected, ..] -> selected
        [] -> fallback
      }
    }
  }
}

/// Capitalizes the first character of a word.
pub fn capitalize_first(word: String) -> String {
  case string.pop_grapheme(word) {
    Ok(#(first_char, remaining)) -> string.uppercase(first_char) <> remaining
    Error(_) -> word
  }
}

/// BEAM random: returns a random integer from 1 to n (inclusive).
@external(erlang, "rand", "uniform")
fn rand_uniform(max: Int) -> Int
