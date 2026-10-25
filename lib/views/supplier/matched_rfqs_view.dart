import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../viewmodels/supplier/matched_rfqs_view_model.dart';
import '../widgets/common.dart';
import '../widgets/flex_table.dart';
import '../widgets/form_fields.dart';
import 'matched_rfq_tile.dart';

class MatchedRfqsView extends StatelessWidget {
  const MatchedRfqsView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MatchedRfqsViewModel>();
    final rows = vm.visible;

    return PageScaffold(
      children: [
        const PageHeader(title: 'Matched RFQs', subtitle: 'RFQs automatically matched to products in your catalog.'),
        SectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SearchField(hint: 'Search RFQs', initialValue: vm.query, onChanged: vm.setQuery),
                ),
              ),
              const Divider(height: 1),
              if (vm.isLoading)
                const LoadingView()
              else if (vm.loadError != null)
                ErrorView(message: vm.loadError!, onRetry: vm.load)
              else if (!vm.hasAny)
                EmptyView(
                  icon: Icons.track_changes,
                  title: 'No matched RFQs yet',
                  message: 'RFQs are matched to your catalog by category and product keywords.',
                  action: OutlinedButton(
                    onPressed: () => context.go(Routes.supplierProducts),
                    child: const Text('Review my products'),
                  ),
                )
              else if (rows.isEmpty)
                const EmptyView(icon: Icons.search_off, title: 'No RFQs match your search')
              else
                FlexTable(
                  rowHeight: 60,
                  columns: const [
                    FlexColumn('Match', flex: 2),
                    FlexColumn('RFQ', flex: 7),
                    FlexColumn('Contractor', flex: 6),
                    FlexColumn('Location', flex: 4),
                    FlexColumn('Required by', flex: 3),
                    FlexColumn('Action', flex: 3, align: TextAlign.right),
                  ],
                  rows: [
                    for (final m in rows)
                      [
                        MatchBadge(m.matchScore),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(m.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 3),
                            CodeText('${m.rfqCode} · ${m.itemCount} items', size: 11, color: AppColors.textMuted),
                          ],
                        ),
                        PartyLabel(alias: m.contractorAlias),
                        CellText(m.deliveryLocation, muted: true),
                        CellText(Fmt.date(m.requiredBy), muted: true),
                        BoqActionButton(m: m),
                      ],
                  ],
                  onRowTap: (i) => context.go(Routes.supplierRfq(rows[i].rfqId)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
