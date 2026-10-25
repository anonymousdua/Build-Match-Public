import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/enums.dart';
import '../../models/quotation.dart';
import 'common.dart';
import 'flex_table.dart';

enum BoqDialogAction { reject, hire }

class BoqDialogLine {
  const BoqDialogLine({required this.itemName, required this.unit, this.line});
  final String itemName;
  final UnitType? unit;
  final QuotationLine? line; // null / unpriced = "Not supplied"
}

/// Itemized quotation + details panel (used by both roles).
Future<BoqDialogAction?> showBoqDialog(
  BuildContext context, {
  required String title,
  required List<BoqDialogLine> lines,
  required double total,
  required String partyLabel,
  required String partyAlias,
  required QuotationStatus status,
  String? revealedName,
  String? revealedEmail,
  DateTime? deliveryDate,
  DateTime? validUntil,
  String? notes,
  List<BoqDialogAction> actions = const [],
}) {
  return showDialog<BoqDialogAction>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.cancel_outlined),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: _Itemized(lines: lines, total: total)),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _Details(
                          partyLabel: partyLabel,
                          partyAlias: partyAlias,
                          revealedName: revealedName,
                          revealedEmail: revealedEmail,
                          status: status,
                          deliveryDate: deliveryDate,
                          validUntil: validUntil,
                          notes: notes,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (actions.contains(BoqDialogAction.reject))
                      OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(BoqDialogAction.reject),
                        child: const Text('Reject', style: TextStyle(color: AppColors.danger)),
                      ),
                    const SizedBox(width: 10),
                    if (actions.contains(BoqDialogAction.hire))
                      ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(BoqDialogAction.hire),
                        child: const Text('Mark as hired'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _Itemized extends StatelessWidget {
  const _Itemized({required this.lines, required this.total});
  final List<BoqDialogLine> lines;
  final double total;

  @override
  Widget build(BuildContext context) {
    Widget availability(QuotationLine? l) {
      if (l == null || !l.isSupplied) return const CellText('Not supplied', muted: true);
      final (label, color) = switch (l.availability ?? Availability.inStock) {
        Availability.inStock => ('In stock', AppColors.greenFg),
        Availability.partial => ('Partial', AppColors.amberFg),
        Availability.onOrder => ('On order', AppColors.blueFg),
      };
      return Text(label, style: TextStyle(color: color, fontSize: 14));
    }

    return SectionCard(
      title: 'Itemized quotation',
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlexTable(
            rowHeight: 44,
            columns: const [
              FlexColumn('Item', flex: 4),
              FlexColumn('Qty', flex: 2, align: TextAlign.right),
              FlexColumn('Unit price', flex: 2, align: TextAlign.right),
              FlexColumn('Line total', flex: 2, align: TextAlign.right),
              FlexColumn('Availability', flex: 2),
            ],
            rows: [
              for (final l in lines)
                [
                  CellText(l.line?.productName == null ? l.itemName : '${l.itemName}\n${l.line!.productName}'),
                  CellText(l.line?.isSupplied ?? false ? '${Fmt.qty(l.line!.quantity)} ${l.unit?.label ?? ''}' : '—'),
                  CellText(l.line?.isSupplied ?? false ? Fmt.aed(l.line!.unitPrice) : '—'),
                  CellText(l.line?.isSupplied ?? false ? Fmt.aed(l.line!.lineTotal) : '—'),
                  availability(l.line),
                ],
            ],
          ),
          Container(
            color: AppColors.tableHeader,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Expanded(child: Text('Grand total', style: TextStyle(fontWeight: FontWeight.w600))),
                Text(Fmt.aed(total), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({
    required this.partyLabel,
    required this.partyAlias,
    required this.status,
    this.revealedName,
    this.revealedEmail,
    this.deliveryDate,
    this.validUntil,
    this.notes,
  });

  final String partyLabel;
  final String partyAlias;
  final String? revealedName;
  final String? revealedEmail;
  final QuotationStatus status;
  final DateTime? deliveryDate;
  final DateTime? validUntil;
  final String? notes;

  @override
  Widget build(BuildContext context) {
    Widget block(String label, Widget value) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 4),
              value,
            ],
          ),
        );
    const v = TextStyle(fontWeight: FontWeight.w500, fontSize: 14);

    return SectionCard(
      title: 'Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          block(partyLabel, PartyLabel(alias: partyAlias, revealedName: revealedName, bold: true, fontSize: 14)),
          if (revealedEmail != null) block('Email', SelectableText(revealedEmail!, style: v)),
          block('Status', QuotationStatusBadge(status)),
          block('Delivery date', Text(Fmt.date(deliveryDate), style: v)),
          block('Valid until', Text(Fmt.date(validUntil), style: v)),
          if ((notes ?? '').isNotEmpty)
            block(
              'Notes',
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
                child: Text(notes!, style: const TextStyle(fontSize: 13, height: 1.4)),
              ),
            ),
        ],
      ),
    );
  }
}
