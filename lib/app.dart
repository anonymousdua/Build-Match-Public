import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'services/auth_repository.dart';
import 'services/category_repository.dart';
import 'services/product_repository.dart';
import 'services/quotation_repository.dart';
import 'services/rfq_repository.dart';
import 'services/supabase_service.dart';
import 'viewmodels/session_view_model.dart';

/// Wires repositories (services layer) and the app-wide session, then
/// hands navigation to go_router.
class BuildMatchApp extends StatelessWidget {
  const BuildMatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    final client = SupabaseService.client;
    return MultiProvider(
      providers: [
        Provider<AuthRepository>(create: (_) => SupabaseAuthRepository(client)),
        Provider<ProfileRepository>(create: (_) => SupabaseProfileRepository(client)),
        Provider<CategoryRepository>(create: (_) => SupabaseCategoryRepository(client)),
        Provider<RfqRepository>(create: (_) => SupabaseRfqRepository(client)),
        Provider<ProductRepository>(create: (_) => SupabaseProductRepository(client)),
        Provider<QuotationRepository>(create: (_) => SupabaseQuotationRepository(client)),
        ChangeNotifierProvider<SessionViewModel>(
          create: (ctx) => SessionViewModel(ctx.read<AuthRepository>(), ctx.read<ProfileRepository>()),
        ),
      ],
      child: const _RouterHost(),
    );
  }
}

class _RouterHost extends StatefulWidget {
  const _RouterHost();

  @override
  State<_RouterHost> createState() => _RouterHostState();
}

class _RouterHostState extends State<_RouterHost> {
  late final GoRouter _router = buildRouter(context.read<SessionViewModel>());

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'BuildMatch',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: _router,
      // The layout is designed for ≥1180×720 (the desktop window minimum).
      // In a smaller browser window, keep that size and scroll instead of
      // squeezing the sidebar and tables.
      builder: (context, child) => _MinCanvas(child: child ?? const SizedBox.shrink()),
    );
  }
}

class _MinCanvas extends StatelessWidget {
  const _MinCanvas({required this.child});
  final Widget child;

  static const _minWidth = 1180.0;
  static const _minHeight = 720.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final tooNarrow = c.maxWidth < _minWidth;
      final tooShort = c.maxHeight < _minHeight;
      if (!tooNarrow && !tooShort) return child;

      final w = tooNarrow ? _minWidth : c.maxWidth;
      final h = tooShort ? _minHeight : c.maxHeight;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: SizedBox(
            width: w,
            height: h,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: Size(w, h)),
              child: child,
            ),
          ),
        ),
      );
    });
  }
}
