import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/routes.dart';
import '../../core/utils/formatters.dart';
import '../../models/enums.dart';
import '../../viewmodels/contractor/my_rfqs_view_model.dart';
import '../widgets/common.dart';
import '../widgets/flex_table.dart';
import '../widgets/form_fields.dart';
import 'rfq_table.dart';

class MyRfqsView extends StatelessWidget {
  const MyRfqsView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MyRfqsViewModel>();
    final rows = vm.visible;

    bool? sorted(RfqSortField f) => vm.sortField == f ? vm.ascending : null;

    return PageScaffold(
      children: [
        PageHeader(
          title: 'My RFQs',
          subtitle: "All requests for quotation you've published.",
          actions: [
            ElevatedButton.icon(
              onPressed: () => context.go(Routes.contractorNewRfq),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New RFQ'),
            ),
          ],
        ),
        SectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    SearchField(hint: 'Search by title or ID', initialValue: vm.query, onChanged: vm.setQuery),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 210,
                      child: AppDropdown<RfqStatus?>(
                        value: vm.statusFilter,
                        items: [null, ...RfqStatus.values],
                        labelOf: (s) => s?.label ?? 'All statuses',
                        hint: 'All statuses',
                        onChanged: vm.setStatusFilter,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (vm.isLoading)
                const LoadingView()
              else if (vm.loadError != null)
                ErrorView(message: vm.loadError!, onRetry: vm.load)
              else if (!vm.hasAny)
                EmptyView(
                  icon: Icons.description_outlined,
                  title: 'No RFQs yet',
                  message: 'Publish an RFQ to start receiving BOQs from matched suppliers.',
                  action: ElevatedButton(onPressed: () => context.go(Routes.contractorNewRfq), child: const Text('Create RFQ')),
                )
              else if (rows.isEmpty)
                const EmptyView(icon: Icons.search_off, title: 'No matching RFQs', message: 'Try a different search or status.')
              else
                FlexTable(
                  columns: [
                    FlexColumn('RFQ ID', flex: 2, onSort: () => vm.sortBy(RfqSortField.code), sorted: sorted(RfqSortField.code)),
                    FlexColumn('Title', flex: 6, onSort: () => vm.sortBy(RfqSortField.title), sorted: sorted(RfqSortField.title)),
                    const FlexColumn('Location', flex: 4),
                    FlexColumn('Created', flex: 3, onSort: () => vm.sortBy(RfqSortField.created), sorted: sorted(RfqSortField.created)),
                    FlexColumn('Required by', flex: 3, onSort: () => vm.sortBy(RfqSortField.requiredBy), sorted: sorted(RfqSortField.requiredBy)),
                    const FlexColumn('BOQs', flex: 1),
                    FlexColumn('Status', flex: 3, onSort: () => vm.sortBy(RfqSortField.status), sorted: sorted(RfqSortField.status)),
                  ],
                  rows: [
                    for (final r in rows)
                      [
                        CodeText(r.code),
                        CellText(r.title),
                        CellText(r.deliveryLocation, muted: true),
                        CellText(Fmt.date(r.createdAt), muted: true),
                        CellText(Fmt.date(r.requiredBy), muted: true),
                        CellText('${r.boqCount}'),
                        RfqStatusBadge(r.status),
                      ],
                  ],
                  onRowTap: (i) => openRfq(context, rows[i]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
