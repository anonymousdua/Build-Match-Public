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
    );
  }
}
