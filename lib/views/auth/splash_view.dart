import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../viewmodels/session_view_model.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';

/// Shown while the session/profile is loading, or if the profile failed to load.
class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionViewModel>();
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandLogo(size: 44, fontSize: 22),
            const SizedBox(height: 28),
            if (session.status == SessionStatus.profileError) ...[
              Container(
                width: 420,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: ErrorView(message: session.error ?? 'Could not load your account.', onRetry: session.retry),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: session.signOut,
                child: const Text('Log out', style: TextStyle(color: Colors.white)),
              ),
            ] else
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accent),
              ),
          ],
        ),
      ),
    );
  }
}
