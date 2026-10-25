import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/routes.dart';
import '../../core/utils/formatters.dart';
import '../../viewmodels/contractor/contractor_dashboard_view_model.dart';
import '../widgets/common.dart';
import '../widgets/flex_table.dart';
import 'rfq_table.dart';

class ContractorDashboardView extends StatelessWidget {
  const ContractorDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ContractorDashboardViewModel>();
    final s = vm.stats;

    return PageScaffold(
      children: [
        PageHeader(
          title: '${Fmt.greeting()} 👷',
          subtitle: "Here's what's happening with your RFQs.",
          actions: [
            ElevatedButton.icon(
              onPressed: () => context.go(Routes.contractorNewRfq),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New RFQ'),
            ),
          ],
        ),
        if (vm.loadError != null)
          SectionCard(child: ErrorView(message: vm.loadError!, onRetry: vm.load))
        else ...[
          StatRow(cards: [
            StatCard(label: 'Total RFQs', value: '${s.totalRfqs}', caption: 'All time', icon: Icons.description_outlined),
            StatCard(label: 'Open', value: '${s.openRfqs}', caption: 'Awaiting decision', icon: Icons.folder_open_outlined),
            StatCard(
              label: 'BOQs received',
              value: '${s.boqsReceived}',
              caption: s.boqsThisWeek > 0 ? '+${s.boqsThisWeek} this week' : 'None this week',
              icon: Icons.inbox_outlined,
            ),
            StatCard(label: 'Hired', value: '${s.hiredRfqs}', caption: 'Suppliers engaged', icon: Icons.check_circle_outline),
          ]),
          const SizedBox(height: 24),
          SectionCard(
            title: 'Recent RFQs',
            padding: EdgeInsets.zero,
            trailing: TextButton(onPressed: () => context.go(Routes.contractorRfqs), child: const Text('View all')),
            child: vm.isLoading
                ? const LoadingView()
                : vm.recent.isEmpty
                    ? EmptyView(
                        icon: Icons.description_outlined,
                        title: 'No RFQs yet',
                        message: 'Create your first RFQ and matched suppliers will reply with BOQs.',
                        action: ElevatedButton(
                          onPressed: () => context.go(Routes.contractorNewRfq),
                          child: const Text('Create RFQ'),
                        ),
                      )
                    : FlexTable(
                        columns: const [
                          FlexColumn('RFQ ID', flex: 2),
                          FlexColumn('Title', flex: 6),
                          FlexColumn('Created', flex: 3),
                          FlexColumn('BOQs', flex: 2),
                          FlexColumn('Status', flex: 3),
                        ],
                        rows: [
                          for (final r in vm.recent)
                            [
                              CodeText(r.code),
                              CellText(r.title),
                              CellText(Fmt.date(r.createdAt), muted: true),
                              CellText('${r.boqCount}'),
                              RfqStatusBadge(r.status),
                            ],
                        ],
                        onRowTap: (i) => openRfq(context, vm.recent[i]),
                      ),
          ),
        ],
      ],
    );
  }
}
