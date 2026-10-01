import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:simple_sheet_music/src/constants.dart';

/// Where a chord label is drawn over a note or rest: the root letter (and its
/// accidental) at 1.35 staff spaces, the rest of the name as a superscript at
/// 0.9, both bold serif, with their baseline 2.15 spaces above the staff's
/// top line — as the note and rest renderers draw it. [x] is the label's left
/// edge, in canvas units. Null when there is no label.
Rect? chordLabelRect_(String? label, {required double x, required double staffLineCenterY}) {
  if (label == null || label.isEmpty) return null;
  var rootEnd = 1;
  if (label.length > 1 && (label[1] == '#' || label[1] == 'b' || label[1] == '♯' || label[1] == '♭')) {
    rootEnd = 2;
  }
  TextPainter painter(String text, double size) => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: size, fontWeight: FontWeight.bold, fontFamily: 'serif'),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
  final root = painter(label.substring(0, rootEnd), Constants.staffSpace * 1.35);
  final suffix = label.length > rootEnd ? painter(label.substring(rootEnd), Constants.staffSpace * 0.9) : null;
  final y = staffLineCenterY - Constants.staffSpace * 2 - Constants.staffSpace * 2.15;
  return Rect.fromLTRB(x, y - root.height, x + root.width + (suffix?.width ?? 0), y);
}
