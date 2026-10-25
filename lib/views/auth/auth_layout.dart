import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/brand.dart';

/// Split layout shared by Login and Sign up: blue hero left, form card right.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.card});
  final Widget card;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const Expanded(flex: 46, child: _Hero()),
          Expanded(
            flex: 54,
            child: Container(
              color: AppColors.background,
              alignment: Alignment.center,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 448),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(32, 32, 32, 30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppTheme.radius + 2),
                      border: Border.all(color: AppColors.border),
                      boxShadow: const [BoxShadow(color: Color(0x120F172A), blurRadius: 16, offset: Offset(0, 6))],
                    ),
                    child: card,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.heroTop, AppColors.heroBottom],
        ),
      ),
      child: CustomPaint(
        painter: const _GridPainter(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(44, 44, 44, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandLogo(),
              const Spacer(),
              const Text(
                'Source and Supply Construction\nMaterials with AI.',
                style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.8),
              ),
              const SizedBox(height: 18),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: const Text(
                  'Contractors post RFQs, matched suppliers reply with BOQs. Identities stay hidden until both sides agree to connect.',
                  style: TextStyle(color: Color(0xFFD5DFEC), fontSize: 15, height: 1.55),
                ),
              ),
              const SizedBox(height: 28),
              const _Feature(icon: Icons.account_tree_outlined, text: 'Automatic RFQ-to-supplier matching'),
              const _Feature(icon: Icons.fact_check_outlined, text: 'Side-by-side BOQ comparison'),
              const _Feature(icon: Icons.lock_outline, text: 'Fully aliased RFQ & BOQ exchange'),
              const Spacer(),
              Text(
                '© ${DateTime.now().year} BuildMatch · UAE',
                style: const TextStyle(color: Color(0xFFB8C6D8), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 17, color: AppColors.navy),
          ),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// Faint blueprint grid over the hero gradient.
class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    const step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
