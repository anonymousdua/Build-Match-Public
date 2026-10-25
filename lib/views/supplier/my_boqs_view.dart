import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/routes.dart';
import '../../core/utils/formatters.dart';
import '../../models/enums.dart';
import '../../models/quotation.dart';
import '../../viewmodels/supplier/my_boqs_view_model.dart';
import '../widgets/boq_dialog.dart';
import '../widgets/common.dart';
import '../widgets/flex_table.dart';

class MyBoqsView extends StatelessWidget {
  const MyBoqsView({super.key});

  Future<void> _open(BuildContext context, SupplierQuotation q) async {
    if (q.status == QuotationStatus.draft) {
      context.go(Routes.supplierRfq(q.rfqId)); // continue editing the draft
      return;
    }
    await showBoqDialog(
      context,
      title: q.code,
      lines: [
        for (final l in q.lines) BoqDialogLine(itemName: l.itemName ?? '', unit: l.unit, line: l),
      ],
      total: q.totalAmount,
      // the supplier sees their own alias; the contractor is shown in the list
      partyLabel: 'Contractor',
      partyAlias: q.contractorAlias,
      revealedName: q.isRevealed ? q.contractorCompanyName : null,
      revealedEmail: q.isRevealed ? q.contractorEmail : null,
      status: q.status,
      deliveryDate: q.deliveryDate,
      validUntil: q.validUntil,
      notes: q.notes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MyBoqsViewModel>();

    return PageScaffold(
      children: [
        const PageHeader(title: 'My BOQs', subtitle: "Quotations you've sent and their current status."),
        SectionCard(
          padding: EdgeInsets.zero,
          child: vm.isLoading
              ? const LoadingView()
              : vm.loadError != null
                  ? ErrorView(message: vm.loadError!, onRetry: vm.load)
                  : vm.items.isEmpty
                      ? EmptyView(
                          icon: Icons.send_outlined,
                          title: 'No BOQs yet',
                          message: 'Open a matched RFQ and send a BOQ – it will be tracked here.',
                          action: ElevatedButton(
                            onPressed: () => context.go(Routes.supplierMatched),
                            child: const Text('View matched RFQs'),
                          ),
                        )
                      : FlexTable(
                          columns: const [
                            FlexColumn('BOQ ID', flex: 2),
                            FlexColumn('RFQ', flex: 5),
                            FlexColumn('Contractor', flex: 5),
                            FlexColumn('Total', flex: 3, align: TextAlign.right),
                            FlexColumn('Delivery', flex: 3),
                            FlexColumn('Status', flex: 2),
                          ],
                          rows: [
                            for (final q in vm.items)
                              [
                                CodeText(q.code, size: 11.5),
                                CellText(q.rfqTitle),
                                PartyLabel(alias: q.contractorAlias, revealedName: q.isRevealed ? q.contractorCompanyName : null),
                                CellText(Fmt.aed(q.totalAmount), bold: true),
                                CellText(Fmt.date(q.deliveryDate), muted: true),
                                QuotationStatusBadge(q.status),
                              ],
                          ],
                          onRowTap: (i) => _open(context, vm.items[i]),
                        ),
        ),
      ],
    );
  }
}
