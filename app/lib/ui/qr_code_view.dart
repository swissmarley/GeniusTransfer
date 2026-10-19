import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// A QR code for [data], drawn black on white with the standard four-module
/// quiet zone (cameras need it), whatever the app theme is.
class QrCodeView extends StatelessWidget {
  const QrCodeView({
    super.key,
    required this.data,
    required this.size,
    required this.semanticLabel,
  });

  final String data;
  final double size;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    // Medium error correction survives screen glare and fingerprints.
    // QrPayload.fromString picks the most compact mode per segment, so the
    // upper-case token is encoded in the denser alphanumeric mode.
    final image = QrImage(QrCode(
      payload: QrPayload.fromString(data),
      errorCorrectLevel: QrErrorCorrectLevel.medium,
    ));
    return Semantics(
      label: semanticLabel,
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _QrPainter(image, data),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image, this.data);

  final QrImage image;
  final String data;

  static const _quietZone = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final count = image.moduleCount;
    final module = size.width / (count + 2 * _quietZone);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final dark = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var row = 0; row < count; row++) {
      var col = 0;
      while (col < count) {
        if (!image.isDark(row, col)) {
          col++;
          continue;
        }
        // Draw a horizontal run at once: fewer seams, fewer draw calls.
        final start = col;
        while (col < count && image.isDark(row, col)) {
          col++;
        }
        canvas.drawRect(
          Rect.fromLTWH(
            (start + _quietZone) * module,
            (row + _quietZone) * module,
            (col - start) * module,
            module,
          ).inflate(0.25),
          dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
