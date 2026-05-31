import 'dart:convert';
import 'dart:core';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simple_sheet_music/src/glyph_metadata.dart';
import 'package:simple_sheet_music/src/glyph_path.dart';
import 'package:simple_sheet_music/src/measure/measure.dart';
import 'package:simple_sheet_music/src/music_objects/clef/clef_type.dart';
import 'package:simple_sheet_music/src/sheet_music_metrics.dart';
import 'package:simple_sheet_music/src/sheet_music_renderer.dart';
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
    this.maxCanvasScale,
    this.onSymbolTap,
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

  /// If set, caps the canvas scale for consistent sizing across multiple lines.
  final double? maxCanvasScale;

  final ValueChanged<int>? onSymbolTap;

  @override
  SimpleSheetMusicState createState() => SimpleSheetMusicState();
}

/// The state class for the SimpleSheetMusic widget.
///
/// This class manages the state of the SimpleSheetMusic widget and handles the initialization,
/// font asset loading, and building of the widget.
class SimpleSheetMusicState extends State<SimpleSheetMusic> {
  GlyphPaths? _glyphPath;
  GlyphMetadata? _metadata;
  Future<void>? _loadFuture;
  Object? _cachedRenderKey;
  SheetMusicRenderer? _cachedRenderer;

  FontType get fontType => widget.fontType;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final xml = await rootBundle.loadString(fontType.svgPath);
    final document = XmlDocument.parse(xml);
    final allGlyphs = document.findAllElements('glyph').toSet();
    _glyphPath = GlyphPaths(allGlyphs);
    final json = await rootBundle.loadString(fontType.metadataPath);
    _metadata = GlyphMetadata(jsonDecode(json) as Map<String, dynamic>);
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
      widget.maxCanvasScale,
      widget.onSymbolTap != null,
      widget.measures.length,
      for (final measure in widget.measures)
        Object.hash(
          measure.isNewLine,
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
      maxCanvasScale: widget.maxCanvasScale,
    );

    _cachedRenderKey = renderKey;
    _cachedRenderer = SheetMusicRenderer(
      layout,
      repaintKey: renderKey,
    );
    return _cachedRenderer!;
  }

  @override
  Widget build(BuildContext context) {
    final targetSize = Size(widget.width, widget.height);
    return FutureBuilder(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
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
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final onSymbolTap = widget.onSymbolTap;
              if (onSymbolTap == null) return;
              final scale = renderer.sheetMusicLayout.canvasScale;
              if (scale <= 0) return;
              final canvasPosition = details.localPosition / scale;
              final index = renderer.sheetMusicLayout
                  .hitTestSelectableIndex(canvasPosition);
              if (index != null) onSymbolTap(index);
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
