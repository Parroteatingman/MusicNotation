// ignore_for_file: avoid_dynamic_calls

import 'dart:ui';

import 'package:simple_sheet_music/src/constants.dart';

class GlyphMetadata {
  const GlyphMetadata(this.metadata);
  static final Map<String, dynamic> _cache = {};
  final Map<String, dynamic> metadata;
  Map<String, dynamic> get glyphBBoxes =>
      metadata['glyphBBoxes'] as Map<String, dynamic>;
  Map<String, dynamic> get glyphsWithAnchors =>
      metadata['glyphsWithAnchors'] as Map<String, dynamic>;
  Map<String, dynamic> get engravingDefaults =>
      metadata['engravingDefaults'] as Map<String, dynamic>;

  double get staffLineThickness =>
      (engravingDefaults['staffLineThickness'] as double) *
      Constants.staffSpace;

  // https://github.com/w3c/smufl/issues/70
  // Amount of overhang on one side of the legerline of a note
  double get legerLineExtension =>
      (engravingDefaults['legerLineExtension'] as double) *
      Constants.staffSpace;

  // (metadata['glyphAdvanceWidths']['legerLineWide'] as double) * staffSpace;
  double get legerLineThickness =>
      (engravingDefaults['legerLineThickness'] as double) *
      Constants.staffSpace;

  double get stemThickness =>
      (engravingDefaults['stemThickness'] as double) * Constants.staffSpace;

  /// The thickness of a beam, as the font's engravers set it (half a staff
  /// space in Bravura). The renderer used to guess at this.
  double get beamThickness =>
      (engravingDefaults['beamThickness'] as double? ?? 0.5) *
      Constants.staffSpace;

  /// The gap between one beam and the next of a group.
  double get beamSpacing =>
      (engravingDefaults['beamSpacing'] as double? ?? 0.25) *
      Constants.staffSpace;

  /// The distance between two staff lines — the unit every other measurement
  /// here is expressed in.
  double get staffSpace => Constants.staffSpace;

  /// How far a stem reaches from its note head when nothing crowds it: an
  /// octave, which is the length Gould gives as standard.
  double get standardStemLength => Constants.staffSpace * 3.5;

  /// A stem is never shortened past this, even inside a steep beam group.
  double get shortestStemLength => Constants.staffSpace * 2.5;

  double get minStemLength {
    if (_cache['minStemLength'] != null) {
      return _cache['minStemLength'] as double;
    }
    final stem = glyphBBoxes['stem'];
    final stemNE = stem['bBoxNE'] as List<dynamic>;
    final stemSW = stem['bBoxSW'] as List<dynamic>;
    return _cache['minStemLength'] =
        ((stemNE[1] as double) - (stemSW[1] as double)).abs() *
            Constants.staffSpace;
  }

  double get measureUpperHeight =>
      Constants.staffSpace * 2 + staffLineThickness / 2;
  double get measureLowerHeight =>
      Constants.staffSpace * 2 + staffLineThickness / 2;

  Offset stemRootOffset(String noteHeadMetadataKey, {required bool isStemUp}) {
    final noteHeadMetaData = glyphsWithAnchors[noteHeadMetadataKey];
    final stemRoot = isStemUp
        ? noteHeadMetaData['stemUpSE']
        : noteHeadMetaData['stemDownNW'];
    return Offset(stemRoot[0] as double, -stemRoot[1] as double) *
        Constants.staffSpace;
  }

  Offset flagRootOffset(String metadataKey, {required bool isStemUp}) {
    final flagRoot = isStemUp
        ? glyphsWithAnchors[metadataKey]['stemUpNW']
        : glyphsWithAnchors[metadataKey]['stemDownSW'];
    return Offset(flagRoot[0] as double, -flagRoot[1] as double) *
        Constants.staffSpace;
  }
}
