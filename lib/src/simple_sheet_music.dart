import 'dart:convert';
import 'dart:core';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simple_sheet_music/src/constants.dart';
import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/glyph_path.dart';
import 'package:simple_sheet_music/src/measure/measure.dart';
import 'package:simple_sheet_music/src/music_objects/clef/clef_type.dart';
import 'package:simple_sheet_music/src/sheet_music_metrics.dart';
import 'package:simple_sheet_music/src/sheet_music_renderer.dart';
import 'package:simple_sheet_music/src/sheet_symbol_box.dart';
import 'package:xml/xml.dart';

import 'font_types.dart';
import 'music_objects/interface/musical_symbol.dart';
import 'music_objects/key_signature/keysignature_type.dart';
import 'sheet_music_layout.dart';

typedef OnTapMusicObjectCallback = void Function(
  MusicalSymbol musicObject,
  Offset offset,
);

/// The `SimpleSheetMusic` widget is used to display sheet music.
/// It takes a list of `Staff` objects, an initial clef, and other optional parameters to customize the appearance of the sheet music.
class SimpleSheetMusic extends StatefulWidget {
  const SimpleSheetMusic({
    super.key,
    required this.measures,
    this.initialClefType = ClefType.treble,
    this.initialKeySignatureType = KeySignatureType.cMajor,
    this.height = 400.0,
    this.width = 400.0,
    this.lineColor = Colors.black54,
    this.fontType = FontType.bravura,
    this.showBarlines = true,
    this.showEndBarline = true,
    this.showFinalBarline = true,
    this.extendStaffToFullWidth = false,
    this.alignLeft = false,
    this.distributeSymbolsToFullWidth = false,
    this.contentHorizontalPadding = 0,
    this.maxCanvasScale,
    this.minCanvasScale,
    this.onSymbolTap,
    this.onSymbolDragged,
    this.onSymbolDragEnd,
    this.justifyLines = true,
    this.spreadOnlyNotes = false,
    this.minStretch = 1,
    this.caretIndex,
    this.caretColor,
    this.spaceBelowStaff = 0,
    this.onLayout,
  });

  /// The list of measures to be displayed.
  final List<Measure> measures;

  /// Receive maximum width and height so as not to break the aspect ratio of the score.
  final double height;

  /// Receive maximum width and height so as not to break the aspect ratio of the score.
  final double width;

  /// The font type to be used for rendering the sheet music.
  final FontType fontType;

  /// The initial clef  for the sheet music.
  final ClefType initialClefType;

  // / The initial keySignature for the sheet music.
  final KeySignatureType initialKeySignatureType;

  /// A callback function that is called when a music object is tapped.
  // final OnTapMusicObjectCallback? onTap;

  final Color lineColor;

  /// Whether to draw barlines between measures.
  final bool showBarlines;

  final bool showEndBarline;
  final bool showFinalBarline;
  final bool extendStaffToFullWidth;

  /// When true, content is left-aligned instead of horizontally centred.
  final bool alignLeft;

  /// Distributes the gaps between symbols so the first and last glyphs sit at
  /// fixed horizontal insets while preserving their rendered size.
  final bool distributeSymbolsToFullWidth;

  /// Physical horizontal inset used by [distributeSymbolsToFullWidth].
  final double contentHorizontalPadding;

  /// If set, caps the canvas scale for consistent sizing across multiple lines.
  final double? maxCanvasScale;

  /// Never draws the staff smaller than this: a line too long for the width
  /// pulls its notes together instead. See [SheetMusicLayout.minCanvasScale].
  final double? minCanvasScale;

  final ValueChanged<int>? onSymbolTap;

  /// Called while a symbol is dragged up or down, with how many staff steps
  /// it has travelled from where the drag began — a step being a line to the
  /// space next to it, which is what moving a note head by one looks like.
  ///
  /// Dragging a note up the staff is how a note's pitch is changed on the
  /// page rather than through a keypad, so this reports the move in the terms
  /// the page reads in, and leaves what to do with it to the caller.
  final void Function(int index, int staffSteps)? onSymbolDragged;

  /// Called when the drag ends, so a caller can close an undo step.
  final VoidCallback? onSymbolDragEnd;

  /// Pull each line but the last out to the full width. See
  /// [SheetMusicLayout.justifyLines].
  final bool justifyLines;

  /// Pull only notes and rests apart when a line is spread to the width;
  /// clefs, key and time signatures and barlines keep their own width. See
  /// [SheetMusicLayout.spreadOnlyNotes].
  final bool spreadOnlyNotes;

  /// See [SheetMusicLayout.minStretch].
  final double minStretch;

  /// Where the next note will be written, counted in notes and rests. Null
  /// draws no caret.
  final int? caretIndex;

  /// The colour of the caret.
  final Color? caretColor;

  /// Room kept under every staff, in staff spaces, for whatever the caller
  /// writes under the notes. The staff scales down to make room, the way it
  /// does for a low note.
  final double spaceBelowStaff;

  /// Where every note, rest and chord was drawn, in this widget's
  /// coordinates. Called after the frame that first draws a layout, and
  /// again whenever the layout changes — never for a repaint alone.
  final ValueChanged<List<SheetSymbolBox>>? onLayout;

  /// Reads and parses [fontType] ahead of the first staff, so that staff
  /// draws on its first frame. The parse runs on a background isolate; a
  /// staff shown meanwhile waits for the same read rather than start one.
  static Future<void> preloadFont([FontType fontType = FontType.bravura]) =>
      _SheetMusicFont.load(fontType);

  /// How wide [measures] are, in points, set as one line at [canvasScale]
  /// (font units to points; a staff space is 250) with every note given the
  /// room its value asks for and nothing squeezed: the width a line needs to
  /// be read at that size. Null until [fontType] has loaded (see
  /// [preloadFont]).
  ///
  /// [spacingFrom] is the page the line will be drawn in, when that is more
  /// than the line itself (one widget drawing several lines spaces them all
  /// against the page's shortest note); left out, the line is measured as a
  /// staff of its own. A caller breaks its lines with this so that a busy
  /// bar moves down rather than drawing the line smaller.
  static double? lineWidth(
    List<Measure> measures, {
    required double canvasScale,
    List<Measure>? spacingFrom,
    FontType fontType = FontType.bravura,
  }) {
    final font = _SheetMusicFont.ready(fontType);
    if (font == null || measures.isEmpty) return null;
    final spacing = spacingFrom == null
        ? null
        : SheetMusicMetrics(
            spacingFrom,
            ClefType.treble,
            KeySignatureType.cMajor,
            font.metadata,
            font.glyphPath,
          ).spacing;
    final line = SheetMusicMetrics(
      [
        for (final measure in measures)
          measure.isNewLine
              ? Measure(
                  measure.musicalSymbols,
                  startRepeat: measure.startRepeat,
                  endBarline: measure.endBarline,
                )
              : measure,
      ],
      ClefType.treble,
      KeySignatureType.cMajor,
      font.metadata,
      font.glyphPath,
      spacing: spacing,
    );
    var width = 0.0;
    for (final staff in line.staffsMetricses) {
      width += staff.objectsWidth * canvasScale + staff.horizontalMarginSum;
    }
    return width;
  }

  /// How many times a staff was laid out (a layout built, not reused).
  /// For tests that check identical input is not laid out again.
  @visibleForTesting
  static int debugLayoutCount = 0;

  @override
  SimpleSheetMusicState createState() => SimpleSheetMusicState();
}

/// The state class for the SimpleSheetMusic widget.
///
/// This class manages the state of the SimpleSheetMusic widget and handles the initialization,
/// font asset loading, and building of the widget.
/// The font's glyphs and metrics, read and parsed once per font for the
/// life of the process. The SVG is close to 2 MB, so a page holding a
/// dozen staffs (a sheet of all twelve keys) used to parse it a dozen
/// times over and stall while it did.
class _SheetMusicFont {
  const _SheetMusicFont(this.glyphPath, this.metadata);

  final GlyphPaths glyphPath;
  final GlyphMetadata metadata;

  static final Map<FontType, Future<_SheetMusicFont>> _loading = {};
  static final Map<FontType, _SheetMusicFont> _ready = {};

  /// The parsed font, already there for every staff after the first.
  static _SheetMusicFont? ready(FontType fontType) => _ready[fontType];

  static Future<_SheetMusicFont> load(FontType fontType) {
    return _loading.putIfAbsent(fontType, () async {
      try {
        final xml = await rootBundle.loadString(fontType.svgPath);
        final json = await rootBundle.loadString(fontType.metadataPath);
        final parsed = await _parse(xml, json);
        final font = _SheetMusicFont(
          GlyphPaths(parsed.glyphs),
          GlyphMetadata(parsed.metadata),
        );
        _ready[fontType] = font;
        return font;
      } catch (_) {
        // A failed read must not poison later attempts.
        _loading.removeWhere((key, _) => key == fontType);
        rethrow;
      }
    });
  }

  /// The glyphs and the metadata, parsed off the UI thread: the SVG is
  /// about 2 MB and the metadata 0.75 MB, and parsing them on the main
  /// isolate stalled the first staff shown (a hitch on the first 琶音 or
  /// 音阶 layer, chord card, lick…). `compute` hands the result back
  /// without copying it (the worker exits with it); should the worker
  /// fail, the parse runs here as it always did.
  static Future<_ParsedFont> _parse(String xml, String json) async {
    try {
      return await compute(_parseInWorker, <String>[xml, json]);
    } on Object catch (_) {
      return _parseNow(xml, json);
    }
  }

  static _ParsedFont _parseInWorker(List<String> sources) =>
      _parseNow(sources[0], sources[1]);

  static _ParsedFont _parseNow(String xml, String json) => _ParsedFont(
        XmlDocument.parse(xml).findAllElements('glyph').toSet(),
        jsonDecode(json) as Map<String, dynamic>,
      );
}

/// A font as parsed, before it is wrapped for drawing.
class _ParsedFont {
  const _ParsedFont(this.glyphs, this.metadata);

  final Set<XmlElement> glyphs;
  final Map<String, dynamic> metadata;
}

class SimpleSheetMusicState extends State<SimpleSheetMusic> {
  GlyphPaths? _glyphPath;
  GlyphMetadata? _metadata;
  Future<void>? _loadFuture;
  Object? _cachedRenderKey;
  SheetMusicRenderer? _cachedRenderer;

  /// The layout last reported through [SimpleSheetMusic.onLayout].
  Object? _reportedRenderKey;

  /// The symbol a vertical drag started on, and where it started.
  int? _dragIndex;
  double _dragStartY = 0;
  int _dragSteps = 0;

  /// The symbol drawn under [position], if any.
  int? _symbolAt(SheetMusicRenderer renderer, Offset position) {
    final scale = renderer.sheetMusicLayout.canvasScale;
    if (scale <= 0) return null;
    return renderer.sheetMusicLayout.hitTestSelectableIndex(position / scale);
  }

  FontType get fontType => widget.fontType;

  /// The scale the staff was last drawn at (font units to points: a staff
  /// space is 250 font units), or null before the font has loaded. For
  /// tests that check a staff kept its size.
  @visibleForTesting
  double? get debugCanvasScale =>
      _cachedRenderer?.sheetMusicLayout.canvasScale;

  @override
  void initState() {
    super.initState();
    // Already parsed: draw on the first frame, with no spinner between.
    final ready = _SheetMusicFont.ready(fontType);
    if (ready != null) {
      _glyphPath = ready.glyphPath;
      _metadata = ready.metadata;
    }
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final font = await _SheetMusicFont.load(fontType);
    if (!mounted) {
      return;
    }
    _glyphPath = font.glyphPath;
    _metadata = font.metadata;
  }

  Object _buildRenderKey() {
    return Object.hashAll([
      widget.width,
      widget.height,
      widget.lineColor.toARGB32(),
      widget.fontType,
      widget.initialClefType,
      widget.initialKeySignatureType,
      widget.showBarlines,
      widget.showEndBarline,
      widget.showFinalBarline,
      widget.extendStaffToFullWidth,
      widget.alignLeft,
      widget.distributeSymbolsToFullWidth,
      widget.contentHorizontalPadding,
      widget.maxCanvasScale,
      widget.minCanvasScale,
      widget.onSymbolTap != null,
      widget.onSymbolDragged != null,
      widget.justifyLines,
      widget.spreadOnlyNotes,
      widget.minStretch,
      widget.caretIndex,
      widget.caretColor?.toARGB32(),
      widget.spaceBelowStaff,
      widget.measures.length,
      for (final measure in widget.measures)
        Object.hash(
          measure.isNewLine,
          measure.startRepeat,
          measure.endBarline,
          measure.musicalSymbols.length,
          Object.hashAll(
            measure.musicalSymbols.map(identityHashCode),
          ),
        ),
    ]);
  }

  SheetMusicRenderer _resolveRenderer() {
    final renderKey = _buildRenderKey();
    if (_cachedRenderer != null && _cachedRenderKey == renderKey) {
      return _cachedRenderer!;
    }

    SimpleSheetMusic.debugLayoutCount++;
    final metricsBuilder = SheetMusicMetrics(
      widget.measures,
      widget.initialClefType,
      widget.initialKeySignatureType,
      _metadata!,
      _glyphPath!,
    );
    final layout = SheetMusicLayout(
      metricsBuilder,
      widget.lineColor,
      widgetWidth: widget.width,
      widgetHeight: widget.height,
      showBarlines: widget.showBarlines,
      showEndBarline: widget.showEndBarline,
      showFinalBarline: widget.showFinalBarline,
      extendStaffToFullWidth: widget.extendStaffToFullWidth,
      alignLeft: widget.alignLeft,
      distributeSymbolsToFullWidth: widget.distributeSymbolsToFullWidth,
      contentHorizontalPadding: widget.contentHorizontalPadding,
      maxCanvasScale: widget.maxCanvasScale,
      minCanvasScale: widget.minCanvasScale,
      justifyLines: widget.justifyLines,
      spreadOnlyNotes: widget.spreadOnlyNotes,
      minStretch: widget.minStretch,
      caretIndex: widget.caretIndex,
      caretColor: widget.caretColor,
      spaceBelowStaff: widget.spaceBelowStaff * Constants.staffSpace,
    );

    _cachedRenderKey = renderKey;
    _cachedRenderer = SheetMusicRenderer(
      layout,
      repaintKey: renderKey,
    );
    return _cachedRenderer!;
  }

  /// Tells [SimpleSheetMusic.onLayout] where the symbols are, once per
  /// layout, after the frame that draws it.
  void _reportLayout(SheetMusicRenderer renderer) {
    if (widget.onLayout == null) return;
    final key = _cachedRenderKey;
    if (key == null || key == _reportedRenderKey) return;
    _reportedRenderKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _cachedRenderKey != key) return;
      widget.onLayout?.call(renderer.sheetMusicLayout.symbolBoxes());
    });
  }

  @override
  Widget build(BuildContext context) {
    final targetSize = Size(widget.width, widget.height);
    return FutureBuilder(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done &&
            (_glyphPath == null || _metadata == null)) {
          // The music font is still loading: the stave's space, empty — no
          // spinner.
          return SizedBox(
            key: const ValueKey('simple-sheet-music-loading'),
            width: widget.width,
            height: widget.height,
          );
        }
        if (snapshot.hasError || _glyphPath == null || _metadata == null) {
          return Center(
            child: Text(
              'Error loading music fonts: ${snapshot.error}',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          );
        }
        try {
          final renderer = _resolveRenderer();
          _reportLayout(renderer);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final onSymbolTap = widget.onSymbolTap;
              if (onSymbolTap == null) return;
              final index = _symbolAt(renderer, details.localPosition);
              if (index != null) onSymbolTap(index);
            },
            // Vertical only, so a staff inside a horizontal scroller still
            // scrolls and a drag on a note still moves the note.
            //
            // The note is found on the way down rather than when the drag is
            // recognised: by then the finger has travelled the slop distance
            // and has usually left the note head it started on.
            onVerticalDragDown: widget.onSymbolDragged == null
                ? null
                : (details) {
                    _dragIndex = _symbolAt(renderer, details.localPosition);
                    _dragStartY = details.localPosition.dy;
                    _dragSteps = 0;
                  },
            onVerticalDragUpdate: widget.onSymbolDragged == null
                ? null
                : (details) {
                    final index = _dragIndex;
                    if (index == null) return;
                    final scale = renderer.sheetMusicLayout.canvasScale;
                    if (scale <= 0) return;
                    // A staff step is half the gap between two lines.
                    final stepHeight = Constants.staffSpace * scale / 2;
                    if (stepHeight <= 0) return;
                    final steps =
                        ((_dragStartY - details.localPosition.dy) / stepHeight)
                            .round();
                    if (steps == _dragSteps) return;
                    _dragSteps = steps;
                    widget.onSymbolDragged!(index, steps);
                  },
            onVerticalDragEnd: widget.onSymbolDragged == null
                ? null
                : (_) {
                    if (_dragIndex != null) widget.onSymbolDragEnd?.call();
                    _dragIndex = null;
                  },
            onVerticalDragCancel: widget.onSymbolDragged == null
                ? null
                : () {
                    if (_dragIndex != null) widget.onSymbolDragEnd?.call();
                    _dragIndex = null;
                  },
            child: RepaintBoundary(
              child: CustomPaint(
                size: targetSize,
                painter: renderer,
                isComplex: true,
              ),
            ),
          );
        } on Object catch (e) {
          return Center(
            child: Text(
              'Render error: $e',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          );
        }
      },
    );
  }
}
