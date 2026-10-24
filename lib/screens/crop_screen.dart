import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// ছবির বর্গাকার অংশ বাছাই — আঙুলে সরানো ও পিঞ্চ করে বড়-ছোট করা যায়।
/// গোল দাগটা অ্যাভাটারে যতটুকু দেখা যাবে তা দেখায়। ফেরত দেয় মূল ছবির
/// পিক্সেলে কাটার অংশ; বাতিল করলে null।
Future<Rect?> cropSquare(BuildContext context, Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final size = Size(
    frame.image.width.toDouble(),
    frame.image.height.toDouble(),
  );
  frame.image.dispose();
  codec.dispose();
  if (!context.mounted) return null;
  return Navigator.of(context).push<Rect>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _CropScreen(bytes: bytes, imageSize: size),
    ),
  );
}

class _CropScreen extends StatefulWidget {
  const _CropScreen({required this.bytes, required this.imageSize});
  final Uint8List bytes;
  final Size imageSize;

  @override
  State<_CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<_CropScreen> {
  static const _maxZoom = 5.0;

  /// বর্গের বাইরে চারপাশের ফাঁকা জায়গা।
  static const _gap = 24.0;

  /// কাটার বর্গ (স্ক্রিনের মাপে) — লেআউটে হিসাব হয়।
  Rect _square = Rect.zero;

  /// ছবি বর্গটা ঠিক ঢেকে ফেলতে যে স্কেল লাগে।
  double _cover = 1;

  /// _cover-এর উপরে কতটা জুম (১ = পুরো বর্গ ঢাকা)।
  double _zoom = 1;

  /// স্ক্রিনে ছবির উপর-বাম কোণ।
  Offset? _offset;

  double _startZoom = 1;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  Size get _shown => widget.imageSize * (_cover * _zoom);

  void _layout(Size area) {
    final side = math.min(area.width, area.height) - _gap * 2;
    final square = Rect.fromCenter(
      center: area.center(Offset.zero),
      width: side,
      height: side,
    );
    if (square == _square && _offset != null) return;
    _square = square;
    _cover = side / math.min(widget.imageSize.width, widget.imageSize.height);
    final shown = _shown;
    _offset = _clamp(
      _offset ?? square.center - Offset(shown.width / 2, shown.height / 2),
    );
  }

  /// ছবি যেন বর্গের কোনো অংশ ফাঁকা না রাখে।
  Offset _clamp(Offset o) {
    final shown = _shown;
    return Offset(
      o.dx.clamp(_square.right - shown.width, _square.left),
      o.dy.clamp(_square.bottom - shown.height, _square.top),
    );
  }

  void _onStart(ScaleStartDetails d) {
    _startZoom = _zoom;
    _startOffset = _offset!;
    _startFocal = d.localFocalPoint;
  }

  void _onUpdate(ScaleUpdateDetails d) {
    setState(() {
      _zoom = (_startZoom * d.scale).clamp(1.0, _maxZoom);
      // আঙুলের নিচের বিন্দুটা আঙুলের সাথেই থাকে
      final anchor = (_startFocal - _startOffset) / _startZoom;
      _offset = _clamp(d.localFocalPoint - anchor * _zoom);
    });
  }

  void _reset() => setState(() {
    _zoom = 1;
    final shown = _shown;
    _offset = _clamp(
      _square.center - Offset(shown.width / 2, shown.height / 2),
    );
  });

  void _done() {
    final scale = _cover * _zoom;
    final topLeft = (_square.topLeft - _offset!) / scale;
    final side = _square.width / scale;
    final bounds = Offset.zero & widget.imageSize;
    Navigator.pop(
      context,
      Rect.fromLTWH(topLeft.dx, topLeft.dy, side, side).intersect(bounds),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('ছবি ঠিক করুন'),
        actions: [
          IconButton(
            tooltip: 'আগের মতো',
            icon: const Icon(Icons.fit_screen_rounded),
            onPressed: _reset,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          _layout(box.biggest);
          final shown = _shown;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onStart,
            onScaleUpdate: _onUpdate,
            onDoubleTap: _reset,
            child: Stack(
              children: [
                Positioned(
                  left: _offset!.dx,
                  top: _offset!.dy,
                  width: shown.width,
                  height: shown.height,
                  child: Image.memory(
                    widget.bytes,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _MaskPainter(_square)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('বাতিল'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _done,
                  child: const Text('ঠিক আছে'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// বর্গের বাইরে অন্ধকার, ভেতরে অ্যাভাটারের গোল দাগ।
class _MaskPainter extends CustomPainter {
  _MaskPainter(this.square);
  final Rect square;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(square),
      Paint()..color = Colors.black.withValues(alpha: .6),
    );
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(square)
        ..addOval(square),
      Paint()..color = Colors.black.withValues(alpha: .3),
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white70
      ..strokeWidth = 1;
    canvas.drawRect(square, line);
    canvas.drawOval(square, line..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_MaskPainter old) => old.square != square;
}
