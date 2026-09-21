/// Enum representing different types of rests in sheet music.
enum RestType {
  whole(_wholePathKey, offsetSpace: 1),
  half(_halfPathKey),
  quarter(_quarterPathKey),
  eighth(_eighthPathKey),
  sixteenth(_sixteenthPathKey),
  thirtySecond(_thirtySecondPathKey),
  sixtyFourth(_sixtyFourthPathKey),
  hundredTwentyEighth(_hundredTwentyEighthPathKey);

  const RestType(this.pathKey, {this.offsetSpace = 0});

  /// The key used to retrieve the path of the rest symbol.
  final String pathKey;

  /// The number of offset spaces for the rest symbol.
  final int offsetSpace;

  static const _wholePathKey = 'uniE4E3';
  static const _halfPathKey = 'uniE4E4';
  static const _quarterPathKey = 'uniE4E5';
  static const _eighthPathKey = 'uniE4E6';
  static const _sixteenthPathKey = 'uniE4E7';
  static const _thirtySecondPathKey = 'uniE4E8';
  static const _sixtyFourthPathKey = 'uniE4E9';
  static const _hundredTwentyEighthPathKey = 'uniE4EA';
}

/// The written value of a rest, counted in quarter notes, so rests claim the
/// same width as the notes they stand in for.
extension RestTypeUnits on RestType {
  double get quarterUnits {
    switch (this) {
      case RestType.whole:
        return 4;
      case RestType.half:
        return 2;
      case RestType.quarter:
        return 1;
      case RestType.eighth:
        return 0.5;
      case RestType.sixteenth:
        return 0.25;
      case RestType.thirtySecond:
        return 0.125;
      case RestType.sixtyFourth:
        return 0.0625;
      case RestType.hundredTwentyEighth:
        return 0.03125;
    }
  }
}
