import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/glyph_path.dart';
import 'package:simple_sheet_music/src/measure/measure_renderer.dart';
import 'package:simple_sheet_music/src/music_objects/notes/single_note/note.dart';
import 'package:simple_sheet_music/src/music_objects/rest/rest.dart';

/// What a [MeasureMark] is.
enum MeasureMarkKind {
  /// The segno sign: where a D.S. goes back to.
  segno,

  /// The coda sign: where "To Coda" leaves from, and where the coda starts.
  coda,

  /// A rehearsal mark, its text in a box: A, B, Intro.
  rehearsal,

  /// Words: D.S. al Coda, D.C. al Fine, To Coda, Fine.
  words,
}

/// A mark printed over a measure besides its notes and chord names, in a
/// band of its own above the chord names (see [MarkBand]).
class MeasureMark {
  const MeasureMark.segno({this.at = 0, this.color = const Color(0xFF000000)})
      : kind = MeasureMarkKind.segno,
        text = null;

  const MeasureMark.coda({this.at = 0, this.color = const Color(0xFF000000)})
      : kind = MeasureMarkKind.coda,
        text = null;

  const MeasureMark.rehearsal(String this.text,
      {this.at = 0, this.color = const Color(0xFF000000)})
      : kind = MeasureMarkKind.rehearsal;

  const MeasureMark.words(String this.text,
      {this.at, this.color = const Color(0xFF000000)})
      : kind = MeasureMarkKind.words;

  /// How much higher, in staff spaces, a line with marks (or an ending)
  /// reaches than one with chord names alone: the band they are set in.
  static const double bandSpaces = 8.0 - 5.4;

  final MeasureMarkKind kind;

  /// What a rehearsal mark or words say.
  final String? text;

  /// Over which of the measure's notes and rests it stands, counted from 0:
  /// 0 is the measure's start. Null: at the measure's end, against its
  /// barline (where a D.S. or a Fine is printed).
  final int? at;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is MeasureMark &&
      other.kind == kind &&
      other.text == text &&
      other.at == at &&
      other.color == color;

  @override
  int get hashCode => Object.hash(kind, text, at, color);
}

/// An ending (a volta, 1. / 2.) over a measure: the bracket over the endings
/// of a repeat, drawn across every measure it holds in a line.
class Volta {
  const Volta(
    this.label, {
    this.starts = true,
    this.ends = true,
    this.closed = true,
    this.color = const Color(0xFF000000),
  });

  /// Printed where the bracket starts: "1.", "2.", "1, 2.".
  final String label;

  /// The bracket starts over this measure: its hook down and [label].
  final bool starts;

  /// The bracket ends over this measure ...
  final bool ends;

  /// ... with a hook down at its end (an open last ending has none).
  final bool closed;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is Volta &&
      other.label == label &&
      other.starts == starts &&
      other.ends == ends &&
      other.closed == closed &&
      other.color == color;

  @override
  int get hashCode => Object.hash(label, starts, ends, closed, color);
}

/// What a mark over a line is, as drawn: for [SheetMarkBox].
enum SheetMarkKind { segno, coda, rehearsal, words, voltaLabel, voltaLine }

/// One mark drawn over a line, in canvas units, and the measure (of the
/// line, from 0) it belongs to.
class PlacedMark {
  PlacedMark(this.kind, this.rect, this.measure, this._paint);

  final SheetMarkKind kind;
  Rect rect;
  final int measure;
  final void Function(Canvas canvas, Rect rect) _paint;

  void paint(Canvas canvas) => _paint(canvas, rect);
}

/// The band over a line's chord names where its segno and coda signs,
/// rehearsal marks, jumps (D.S. al Coda, Fine) and endings are set: the
/// bracket of an ending across its top, the rest under it, side by side —
/// a mark that would run into the one before it moves along to its right.
/// Text is the chord names' serif: rehearsal marks bold in a box, words
/// italic; the signs are the music font's own (Bravura).
class MarkBand {
  const MarkBand._();

  static const double _space = Constants.staffSpace;

  /// How far over the middle of the staff a line that has marks reaches:
  /// the ending's bracket and its stroke.
  static const double upperHeight = 8.0 * _space;

  /// The bracket of an ending, over the middle of the staff.
  static const double _voltaY = 7.75 * _space;
  static const double _voltaHook = 1.5 * _space;
  static const double _stroke = 0.12 * _space;

  /// The marks' foot, over the middle of the staff: clear of the chord
  /// names' tops (5.75 spaces up).
  static const double _foot = 5.95 * _space;
  static const double _gap = 0.35 * _space;
  static const double _signHeight = 1.5 * _space;
  static const double _textSize = 1.05 * _space;

  static TextPainter _text(String text, Color color,
          {required bool bold, bool italic = false, double size = _textSize}) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: size,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            fontFamily: 'serif',
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();

  /// Where the notes and rests of [measure] start across the line.
  static List<double> _noteXs(MeasureRenderer measure) => [
        for (final symbol in measure.symbolRenderers)
          if (symbol is NoteRenderer)
            symbol.noteHeadBounds.left
          else if (symbol is RestRenderer)
            symbol.renderPath.getBounds().left,
      ];

  /// Every mark over the line of [measures], placed. [lineEnd]: where the
  /// line's staff (and its last barline) ends, when it runs on past its last
  /// measure's notes.
  static List<PlacedMark> place(
      List<MeasureRenderer> measures, GlyphPaths paths,
      {double? lineEnd, double lift = 0}) {
    double rightOf(int i) {
      final m = measures[i];
      final end = m.measureOriginX + m.width;
      return i == measures.length - 1 && lineEnd != null
          ? math.max(end, lineEnd)
          : end;
    }

    if (measures.every((m) =>
        m.measureMetrics.marks.isEmpty && m.measureMetrics.volta == null)) {
      return const [];
    }
    // the band moves up with the chord names under it
    final c = measures.first.staffLineCenterY - lift;
    final foot = c - _foot;
    final out = <PlacedMark>[];
    final band = <PlacedMark>[];

    // the endings: one bracket across the measures each holds in the line
    double? from;
    for (var i = 0; i < measures.length; i++) {
      final m = measures[i];
      final volta = m.measureMetrics.volta;
      if (volta == null) {
        from = null;
        continue;
      }
      final left = m.measureOriginX;
      final right = rightOf(i);
      final y = c - _voltaY;
      if (from == null || volta.starts) {
        from = volta.starts ? left + 0.15 * _space : left;
        if (volta.starts) {
          final hook = Rect.fromLTRB(
              from, y - _stroke / 2, from + _stroke, y + _voltaHook);
          out.add(PlacedMark(SheetMarkKind.voltaLine, hook, i,
              (canvas, r) => canvas.drawRect(r, Paint()..color = volta.color)));
          final label =
              _text(volta.label, volta.color, bold: true, size: 1.0 * _space);
          band.add(PlacedMark(
            SheetMarkKind.voltaLabel,
            Rect.fromLTWH(from + 0.3 * _space, y + _stroke + 0.08 * _space,
                label.width, label.height),
            i,
            (canvas, r) => label.paint(canvas, r.topLeft),
          ));
        }
      }
      if (volta.ends || i == measures.length - 1) {
        final end = volta.ends ? right - 0.25 * _space : right;
        final line = Rect.fromLTRB(from, y - _stroke / 2, end, y + _stroke / 2);
        out.add(PlacedMark(SheetMarkKind.voltaLine, line, i,
            (canvas, r) => canvas.drawRect(r, Paint()..color = volta.color)));
        if (volta.ends && volta.closed) {
          final hook = Rect.fromLTRB(
              end - _stroke, y - _stroke / 2, end, y + _voltaHook);
          out.add(PlacedMark(SheetMarkKind.voltaLine, hook, i,
              (canvas, r) => canvas.drawRect(r, Paint()..color = volta.color)));
        }
        if (volta.ends) from = null;
      }
    }

    // the signs, rehearsal marks and words, each where it is printed
    for (var i = 0; i < measures.length; i++) {
      final m = measures[i];
      if (m.measureMetrics.marks.isEmpty) continue;
      final xs = _noteXs(m);
      final start = m.measureOriginX + 0.3 * _space;
      final end = rightOf(i) - 0.5 * _space;
      for (final mark in m.measureMetrics.marks) {
        final at = mark.at;
        double anchor(double width) {
          if (at == null || at >= xs.length) return end - width;
          if (at <= 0) return start;
          return xs[at];
        }

        if (mark.kind == MeasureMarkKind.segno ||
            mark.kind == MeasureMarkKind.coda) {
          final glyph = paths.parsePath(
              mark.kind == MeasureMarkKind.segno ? 'uniE047' : 'uniE048');
          final b = glyph.getBounds();
          final k = _signHeight / b.height;
          final width = b.width * k;
          final rect = Rect.fromLTWH(
              anchor(width), foot - _signHeight, width, _signHeight);
          band.add(PlacedMark(
            mark.kind == MeasureMarkKind.segno
                ? SheetMarkKind.segno
                : SheetMarkKind.coda,
            rect,
            i,
            (canvas, r) {
              final placed = glyph.transform(_scaleTranslate(
                k,
                r.left - b.left * k,
                r.top - b.top * k,
              ));
              canvas.drawPath(placed, Paint()..color = mark.color);
            },
          ));
        } else if (mark.kind == MeasureMarkKind.rehearsal) {
          final text = _text(mark.text ?? '', mark.color, bold: true, size: 1.2 * _space);
          const padX = 0.22 * _space, padY = 0.1 * _space;
          final width = text.width + 2 * padX;
          final height = text.height + 2 * padY;
          band.add(PlacedMark(
            SheetMarkKind.rehearsal,
            Rect.fromLTWH(anchor(width), foot - height, width, height),
            i,
            (canvas, r) {
              canvas.drawRect(
                r.deflate(0.05 * _space),
                Paint()
                  ..color = mark.color
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 0.1 * _space,
              );
              text.paint(canvas, Offset(r.left + padX, r.top + padY));
            },
          ));
        } else {
          final text =
              _text(mark.text ?? '', mark.color, bold: false, italic: true);
          band.add(PlacedMark(
            SheetMarkKind.words,
            Rect.fromLTWH(anchor(text.width), foot - text.height, text.width,
                text.height),
            i,
            (canvas, r) => text.paint(canvas, r.topLeft),
          ));
        }
      }
    }

    // side by side: one that would run into the one before it moves on
    band.sort((a, b) => a.rect.left.compareTo(b.rect.left));
    var reach = double.negativeInfinity;
    for (final mark in band) {
      if (mark.rect.left < reach + _gap) {
        mark.rect = mark.rect.shift(Offset(reach + _gap - mark.rect.left, 0));
      }
      reach = math.max(reach, mark.rect.right);
    }
    return [...out, ...band];
  }
}

/// A scale then a move, as the matrix [Path.transform] takes.
Float64List _scaleTranslate(double k, double dx, double dy) =>
    Float64List.fromList([
      k, 0, 0, 0, //
      0, k, 0, 0, //
      0, 0, 1, 0, //
      dx, dy, 0, 1, //
    ]);
