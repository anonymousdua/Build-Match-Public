import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/routes.dart';
import '../../viewmodels/supplier/supplier_dashboard_view_model.dart';
import '../widgets/common.dart';
import 'matched_rfq_tile.dart';

class SupplierDashboardView extends StatelessWidget {
  const SupplierDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SupplierDashboardViewModel>();
    final s = vm.stats;

    return PageScaffold(
      children: [
        const PageHeader(title: 'Supplier dashboard', subtitle: 'New RFQs matched to your catalog appear here.'),
        if (vm.loadError != null)
          SectionCard(child: ErrorView(message: vm.loadError!, onRetry: vm.load))
        else ...[
          StatRow(cards: [
            StatCard(label: 'Total products', value: '${s.totalProducts}', icon: Icons.inventory_2_outlined),
            StatCard(
              label: 'Matched RFQs',
              value: '${s.matchedRfqs}',
              caption: s.matchedLast24h > 0 ? '${s.matchedLast24h} new today' : null,
              icon: Icons.track_changes,
            ),
            StatCard(label: 'BOQs sent', value: '${s.boqsSent}', icon: Icons.send_outlined),
            StatCard(label: 'BOQs accepted', value: '${s.boqsAccepted}', icon: Icons.check_circle_outline),
          ]),
          const SizedBox(height: 24),
          SectionCard(
            title: 'Newest matched RFQs',
            padding: EdgeInsets.zero,
            trailing: TextButton(onPressed: () => context.go(Routes.supplierMatched), child: const Text('View all')),
            child: vm.isLoading
                ? const LoadingView()
                : vm.newest.isEmpty
                    ? EmptyView(
                        icon: Icons.track_changes,
                        title: 'No matched RFQs yet',
                        message: s.totalProducts == 0
                            ? 'Add products to your catalog – RFQs are matched against them automatically.'
                            : 'When contractors post RFQs for products you stock, they appear here.',
                        action: s.totalProducts == 0
                            ? ElevatedButton(
                                onPressed: () => context.go(Routes.supplierNewProduct),
                                child: const Text('Add product'),
                              )
                            : null,
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < vm.newest.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            MatchedRfqTile(m: vm.newest[i]),
                          ],
                        ],
                      ),
          ),
        ],
      ],
    );
  }
}
