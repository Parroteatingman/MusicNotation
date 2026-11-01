/// The type of tie connection on a note.
///
/// - [start]: This note is the beginning of a tie (curve drawn from this note to the next).
/// - [stop]: This note is the end of a tie (curve drawn from the previous note to this one).
/// - [both]: This note is both the end of one tie and the start of another.
enum TieType {
  start,
  stop,
  both;

  bool get isStart => this == start || this == both;
  bool get isStop => this == stop || this == both;
}

/// Which way a note's ties bend, when it is not left to the note's stem.
///
/// On a staff of one voice a tie bends away from the stem (a chord's split
/// up and down by its heads); where two voices share a staff the upper
/// voice's ties bend up and the lower voice's down (Gould), whatever the
/// heads.
enum TieDirection {
  up,
  down;

  bool get isDown => this == down;
}
