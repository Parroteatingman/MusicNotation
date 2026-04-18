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
