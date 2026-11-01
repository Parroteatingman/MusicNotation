import 'dart:ui';

import 'package:simple_sheet_music/src/measure/measure.dart';
import 'package:simple_sheet_music/src/music_objects/clef/clef_type.dart';
import 'package:simple_sheet_music/src/music_objects/key_signature/keysignature_type.dart';
import 'package:simple_sheet_music/src/sheet_symbol_box.dart';

/// One staff of a staff system: its measures — as many as every other staff
/// of the system holds, each filling the same time — and the clef and key it
/// starts in.
///
/// The staff draws what its measures hold, as a single staff does: a clef,
/// key or time signature at its start is a symbol of its first measure. The
/// [clef] and [keySignature] here are what the notes are read in until such
/// a symbol says otherwise (a bass staff whose row starts without a clef is
/// still read in the bass clef).
///
/// One voice to a staff: notes, chords (`ChordNote`) and rests one after
/// another. A second voice on a staff is a staff of its own with [voiceOf]
/// set: it is drawn on that staff's lines, its notes lined up beat by beat
/// with every other staff's.
class SheetStaff {
  const SheetStaff(
    this.measures, {
    this.clef = ClefType.treble,
    this.keySignature = KeySignatureType.cMajor,
    this.voiceOf,
  });

  /// A second voice on staff [staff]'s lines (with that staff's [clef] and
  /// [keySignature]): its notes, chords and rests, as many measures as every
  /// staff holds.
  const SheetStaff.voice(
    this.measures, {
    required int staff,
    this.clef = ClefType.treble,
    this.keySignature = KeySignatureType.cMajor,
  }) : voiceOf = staff;

  final List<Measure> measures;
  final ClefType clef;
  final KeySignatureType keySignature;

  /// The staff (counted from 0 at the top) whose lines this voice is drawn
  /// on; null for a staff of its own.
  ///
  /// A voice draws no staff lines, barlines, clef or key of its own — its
  /// measures hold only notes, chords and rests — and takes no room down the
  /// page: its notes reach above and below its staff as that staff's own do.
  /// It is the lower of the two voices: where both voices have notes at
  /// once and their heads would touch, the one with its stem up stands to
  /// the right; in a measure where the other voice has notes, a rest of the
  /// staff stands higher and a rest of the voice lower. A voice's rests are
  /// usually not printed (`Rest.hidden`): such a rest keeps its time and
  /// asks for no room.
  ///
  /// Voices come after every staff of their own in a system's list, so the
  /// staffs keep their numbers ([StaffGroup], `labelStaff`). The system's
  /// geometry gives a voice's notes this voice's number as their staff, and
  /// no box of its own among the staffs.
  final int? voiceOf;

  bool get isVoice => voiceOf != null;
}

/// How a [StaffGroup] is marked at the start of the system.
enum StaffGroupKind {
  /// A brace: the staffs of one instrument (a piano's two hands).
  brace,

  /// A square bracket: a family of instruments.
  bracket,

  /// No sign: the staffs only share their barlines.
  none,
}

/// Staffs [first] to [last] (inclusive, counted from 0 at the top) of a
/// system, marked as one at the system's start and, with [barlinesThrough],
/// sharing barlines drawn through the gaps between them.
///
/// Engraving practice (Gould, *Behind Bars*): a piano's staffs take a brace
/// and barlines through both; the parts of a score each keep barlines of
/// their own, broken between the parts, and the whole system is joined at
/// its start by one line.
class StaffGroup {
  const StaffGroup(
    this.first,
    this.last, {
    this.kind = StaffGroupKind.brace,
    this.barlinesThrough = true,
  }) : assert(first <= last);

  /// A piano's (or any keyboard's) staffs: a brace, barlines through.
  const StaffGroup.grandStaff(this.first, this.last)
      : kind = StaffGroupKind.brace,
        barlinesThrough = true;

  final int first;
  final int last;
  final StaffGroupKind kind;
  final bool barlinesThrough;

  bool contains(int staff) => staff >= first && staff <= last;
}

/// A drawn staff of a system, in the widget's coordinates.
class SheetStaffBox {
  const SheetStaffBox({
    required this.staff,
    required this.top,
    required this.bottom,
    required this.inkTop,
    required this.inkBottom,
  });

  final int staff;

  /// The top and bottom lines of the staff.
  final double top;
  final double bottom;

  /// How far the staff's notes, stems, beams and ledger lines reach above
  /// and below it (never inside the staff's own lines).
  final double inkTop;
  final double inkBottom;

  double get center => (top + bottom) / 2;

  /// The distance between two staff lines.
  double get space => (bottom - top) / 4;
}

/// Where a staff system drew everything, in the widget's coordinates: the
/// staffs, the measures (barline to barline, the same on every staff), and
/// every note, rest and chord with the staff it is on.
class SheetSystemGeometry {
  const SheetSystemGeometry({
    required this.size,
    required this.contentLeft,
    required this.staffs,
    required this.measureLefts,
    required this.measureRights,
    required this.symbols,
  });

  /// The size the system was laid out in.
  final Size size;

  /// The system's opening line, where every staff starts; a brace or a
  /// bracket stands left of it.
  final double contentLeft;

  /// The staffs drawn, top down: a second voice ([SheetStaff.voiceOf]) is
  /// drawn on its staff's lines and has no box of its own.
  final List<SheetStaffBox> staffs;

  /// Where each measure starts and ends across the system.
  final List<double> measureLefts;
  final List<double> measureRights;

  /// Every note, rest and chord of the system, staff by staff: a box's
  /// [SheetSymbolBox.staff] is its staff (a voice's own number, for a
  /// second voice: see [SheetStaff.voiceOf]) and [SheetSymbolBox.order] its
  /// place among that staff's notes, rests and chords.
  final List<SheetSymbolBox> symbols;

  /// The notes, rests and chords of [staff], in order.
  Iterable<SheetSymbolBox> symbolsOn(int staff) =>
      symbols.where((box) => box.staff == staff);

  /// The measure under [x], or null outside every measure.
  int? measureAt(double x) {
    for (var i = 0; i < measureLefts.length; i++) {
      if (x >= measureLefts[i] && x <= measureRights[i]) return i;
    }
    return null;
  }
}

/// How big a staff system is drawn: see `SimpleSheetSystem.measure`.
class SheetSystemExtent {
  const SheetSystemExtent(this.width, this.height);

  /// The width it needs with every note given the room its value asks
  /// for: drawn in this width or more, nothing is squeezed.
  final double width;

  /// The height its staffs, and the notes reaching between them, take.
  final double height;

  @override
  String toString() => 'SheetSystemExtent($width × $height)';
}
