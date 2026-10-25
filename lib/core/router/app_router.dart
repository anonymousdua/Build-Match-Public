import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../services/auth_repository.dart';
import '../../services/category_repository.dart';
import '../../services/product_repository.dart';
import '../../services/quotation_repository.dart';
import '../../services/rfq_repository.dart';
import '../../viewmodels/auth_view_models.dart';
import '../../viewmodels/contractor/contractor_dashboard_view_model.dart';
import '../../viewmodels/contractor/my_rfqs_view_model.dart';
import '../../viewmodels/contractor/rfq_detail_view_model.dart';
import '../../viewmodels/contractor/rfq_form_view_model.dart';
import '../../viewmodels/session_view_model.dart';
import '../../viewmodels/settings_view_model.dart';
import '../../viewmodels/supplier/create_boq_view_model.dart';
import '../../viewmodels/supplier/matched_rfqs_view_model.dart';
import '../../viewmodels/supplier/my_boqs_view_model.dart';
import '../../viewmodels/supplier/my_products_view_model.dart';
import '../../viewmodels/supplier/product_form_view_model.dart';
import '../../viewmodels/supplier/supplier_dashboard_view_model.dart';
import '../../views/auth/login_view.dart';
import '../../views/auth/signup_view.dart';
import '../../views/auth/splash_view.dart';
import '../../views/contractor/contractor_dashboard_view.dart';
import '../../views/contractor/my_rfqs_view.dart';
import '../../views/contractor/rfq_detail_view.dart';
import '../../views/contractor/rfq_form_view.dart';
import '../../views/settings/settings_view.dart';
import '../../views/shell/app_shell.dart';
import '../../views/supplier/create_boq_view.dart';
import '../../views/supplier/matched_rfqs_view.dart';
import '../../views/supplier/my_boqs_view.dart';
import '../../views/supplier/my_products_view.dart';
import '../../views/supplier/product_form_view.dart';
import '../../views/supplier/supplier_dashboard_view.dart';
import 'routes.dart';

/// go_router configuration with auth + role guards.
/// Each screen gets its own ViewModel, created when the route is built.
GoRouter buildRouter(SessionViewModel session) {
  Page<void> page(GoRouterState state, Widget child) => NoTransitionPage<void>(key: state.pageKey, child: child);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: session,
    redirect: (context, state) => _redirect(session, state.uri.path),
    routes: [
      GoRoute(path: Routes.splash, pageBuilder: (c, s) => page(s, const SplashView())),
      GoRoute(
        path: Routes.login,
        pageBuilder: (c, s) => page(
          s,
          ChangeNotifierProvider(create: (ctx) => LoginViewModel(ctx.read<AuthRepository>()), child: const LoginView()),
        ),
      ),
      GoRoute(
        path: Routes.signup,
        pageBuilder: (c, s) => page(
          s,
          ChangeNotifierProvider(create: (ctx) => SignUpViewModel(ctx.read<AuthRepository>()), child: const SignUpView()),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          // ---------------- Contractor ----------------
          GoRoute(
            path: Routes.contractor,
            pageBuilder: (c, s) => page(
              s,
              ChangeNotifierProvider(
                create: (ctx) => ContractorDashboardViewModel(ctx.read<RfqRepository>())..load(),
                child: const ContractorDashboardView(),
              ),
            ),
          ),
          GoRoute(
            path: Routes.contractorRfqs,
            pageBuilder: (c, s) => page(
              s,
              ChangeNotifierProvider(
                key: ValueKey('rfqs-${s.uri.queryParameters['q']}'),
                create: (ctx) =>
                    MyRfqsViewModel(ctx.read<RfqRepository>(), initialQuery: s.uri.queryParameters['q'])..load(),
                child: const MyRfqsView(),
              ),
            ),
          ),
          GoRoute(
            path: Routes.contractorNewRfq,
            pageBuilder: (c, s) => page(
              s,
              ChangeNotifierProvider(
                create: (ctx) => RfqFormViewModel(ctx.read<RfqRepository>(), ctx.read<CategoryRepository>())..load(),
                child: const RfqFormView(),
              ),
            ),
          ),
          GoRoute(
            path: '/contractor/rfqs/:id/edit',
            pageBuilder: (c, s) => page(
              s,
              ChangeNotifierProvider(
                create: (ctx) => RfqFormViewModel(
                  ctx.read<RfqRepository>(),
                  ctx.read<CategoryRepository>(),
                  rfqId: s.pathParameters['id'],
                )..load(),
                child: const RfqFormView(),
              ),
            ),
          ),
          GoRoute(
            path: '/contractor/rfqs/:id',
            pageBuilder: (c, s) => page(
              s,
              ChangeNotifierProvider(
                key: ValueKey('rfq-${s.pathParameters['id']}'),
                create: (ctx) => RfqDetailViewModel(
                  ctx.read<RfqRepository>(),
                  ctx.read<CategoryRepository>(),
                  s.pathParameters['id']!,
                )..load(),
                child: const RfqDetailView(),
              ),
            ),
          ),
          GoRoute(path: Routes.contractorSettings, pageBuilder: (c, s) => page(s, _settings())),

          // ---------------- Supplier ----------------
          GoRoute(
            path: Routes.supplier,
            pageBuilder: (c, s) => page(
              s,
              ChangeNotifierProvider(
                create: (ctx) => SupplierDashboardViewModel(ctx.read<QuotationRepository>())..load(),
                child: const SupplierDashboardView(),
              ),
            ),
          ),
          GoRoute(
            path: Routes.supplierProducts,
            pageBuilder: (c, s) => page(
              s,
              ChangeNotifierProvider(
                key: ValueKey('products-${s.uri.queryParameters['q']}'),
                create: (ctx) => MyProductsViewModel(
                  ctx.read<ProductRepository>(),
                  ctx.read<CategoryRepository>(),
                  initialQuery: s.uri.queryParameters['q'],
                )..load(),
                child: const MyProductsView(),
              ),
            ),
          ),
          GoRoute(
            path: Routes.supplierNewProduct,
            pageBuilder: (c, s) => page(
              s,
              ChangeNotifierProvider(
                create: (ctx) => ProductFormViewModel(ctx.read<ProductRepository>(), ctx.read<CategoryRepository>())..load(),
                child: const ProductFormView(),
              ),
            ),
          ),
          GoRoute(
            path: '/supplier/products/:id/edit',
            pageBuilder: (c, s) => page(
              s,
              ChangeNotifierProvider(
                create: (ctx) => ProductFormViewModel(
                  ctx.read<ProductRepository>(),
                  ctx.read<CategoryRepository>(),
                  productId: s.pathParameters['id'],
                )..load(),
                child: const ProductFormView(),
              ),
            ),
          ),
          GoRoute(
            path: Routes.supplierMatched,
            pageBuilder: (c, s) => page(
              s,
              ChangeNotifierProvider(
                key: ValueKey('matched-${s.uri.queryParameters['q']}'),
                create: (ctx) => MatchedRfqsViewModel(
                  ctx.read<QuotationRepository>(),
                  initialQuery: s.uri.queryParameters['q'],
                )..load(),
                child: const MatchedRfqsView(),
              ),
            ),
          ),
          GoRoute(
            path: '/supplier/rfqs/:id',
            pageBuilder: (c, s) => page(
              s,
              ChangeNotifierProvider(
                key: ValueKey('boq-${s.pathParameters['id']}'),
                create: (ctx) => CreateBoqViewModel(
                  ctx.read<QuotationRepository>(),
                  ctx.read<ProductRepository>(),
                  s.pathParameters['id']!,
                )..load(),
                child: const CreateBoqView(),
              ),
            ),
          ),
          GoRoute(
            path: Routes.supplierBoqs,
            pageBuilder: (c, s) => page(
              s,
              ChangeNotifierProvider(
                create: (ctx) => MyBoqsViewModel(ctx.read<QuotationRepository>())..load(),
                child: const MyBoqsView(),
              ),
            ),
          ),
          GoRoute(path: Routes.supplierSettings, pageBuilder: (c, s) => page(s, _settings())),
        ],
      ),
    ],
  );
}

Widget _settings() => ChangeNotifierProvider(
      create: (ctx) => SettingsViewModel(
        ctx.read<SessionViewModel>(),
        ctx.read<AuthRepository>(),
        ctx.read<ProfileRepository>(),
      ),
      child: const SettingsView(),
    );

/// Auth + role guard. Returns where to go, or null to stay.
String? _redirect(SessionViewModel session, String path) {
  final isPublic = Routes.publicPaths.contains(path);

  switch (session.status) {
    case SessionStatus.initializing:
    case SessionStatus.loadingProfile:
    case SessionStatus.profileError:
      return path == Routes.splash ? null : Routes.splash;
    case SessionStatus.signedOut:
      return isPublic ? null : Routes.login;
    case SessionStatus.ready:
      break;
  }

  if (isPublic || path == Routes.splash) return session.homeRoute;

  // Role guard: each role may only open its own section.
  final role = session.role;
  if (path.startsWith(Routes.contractor) && role != UserRole.contractor) return session.homeRoute;
  if (path.startsWith(Routes.supplier) && role != UserRole.supplier) return session.homeRoute;
  if (!path.startsWith(Routes.contractor) && !path.startsWith(Routes.supplier)) return session.homeRoute;
  return null;
}
