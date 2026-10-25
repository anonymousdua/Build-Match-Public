import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Orange rounded square with a hard-hat outline, as in the designs.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(size * 0.28)),
      padding: EdgeInsets.all(size * 0.2),
      child: const CustomPaint(painter: HardHatPainter(color: AppColors.navy)),
    );
  }
}

/// "[logo] BuildMatch"
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 36, this.fontSize = 18});
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: size),
        const SizedBox(width: 10),
        Text(
          'BuildMatch',
          style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w700, letterSpacing: -0.3),
        ),
      ],
    );
  }
}

/// Simple line-art hard hat (dome, ridge, brim). Also used as a role icon.
class HardHatPainter extends CustomPainter {
  const HardHatPainter({required this.color, this.strokeWidth});
  final Color color;
  final double? strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth ?? w * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // dome
    final dome = Path()
      ..moveTo(w * 0.18, h * 0.70)
      ..cubicTo(w * 0.18, h * 0.30, w * 0.82, h * 0.30, w * 0.82, h * 0.70);
    canvas.drawPath(dome, p);
    // ridge
    canvas.drawLine(Offset(w * 0.42, h * 0.36), Offset(w * 0.42, h * 0.62), p);
    canvas.drawLine(Offset(w * 0.58, h * 0.36), Offset(w * 0.58, h * 0.62), p);
    // brim
    final brim = RRect.fromLTRBR(w * 0.06, h * 0.70, w * 0.94, h * 0.84, Radius.circular(h * 0.06));
    canvas.drawRRect(brim, p);
  }

  @override
  bool shouldRepaint(covariant HardHatPainter old) => old.color != color || old.strokeWidth != strokeWidth;
}

class HardHatIcon extends StatelessWidget {
  const HardHatIcon({super.key, this.size = 22, this.color = AppColors.primary});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: HardHatPainter(color: color, strokeWidth: 1.6)));
}
