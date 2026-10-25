import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/enums.dart';
import '../../models/quotation.dart';
import '../../models/rfq.dart';
import '../../viewmodels/contractor/rfq_detail_view_model.dart';
import '../widgets/boq_dialog.dart';
import '../widgets/common.dart';
import '../widgets/flex_table.dart';
import '../widgets/form_fields.dart';

class RfqDetailView extends StatelessWidget {
  const RfqDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RfqDetailViewModel>();
    final rfq = vm.rfq;

    if (vm.isLoading && rfq == null) return const LoadingView();
    if (rfq == null) {
      return PageScaffold(children: [
        BackLink(label: 'My RFQs', onTap: () => context.go(Routes.contractorRfqs)),
        const SizedBox(height: 16),
        SectionCard(child: ErrorView(message: vm.loadError ?? 'RFQ not found.', onRetry: vm.load)),
      ]);
    }

    return PageScaffold(
      maxWidth: 1240,
      children: [
        _Header(vm: vm, rfq: rfq),
        if (vm.actionError != null) ErrorBanner(vm.actionError!),
        if (vm.accepted != null) _RevealedBanner(q: vm.accepted!),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: _Summary(vm: vm, rfq: rfq)),
            const SizedBox(width: 20),
            Expanded(flex: 8, child: _Items(vm: vm, rfq: rfq)),
          ],
        ),
        if (vm.attachments.isNotEmpty) ...[
          const SizedBox(height: 20),
          _Attachments(vm: vm),
        ],
        const SizedBox(height: 28),
        if (rfq.status != RfqStatus.draft) ...[
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'BOQs received '),
              TextSpan(text: '(${vm.quotations.length})', style: const TextStyle(color: AppColors.textMuted)),
            ]),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (vm.quotations.isEmpty)
            const SectionCard(
              child: EmptyView(
                title: 'No BOQs yet',
                message: 'Matched suppliers have been notified. BOQs will appear here as they arrive.',
              ),
            )
          else ...[
            _BoqCards(vm: vm),
            const SizedBox(height: 24),
            _Comparison(vm: vm, rfq: rfq),
          ],
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.vm, required this.rfq});
  final RfqDetailViewModel vm;
  final RfqDetail rfq;

  Future<void> _delete(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete ${rfq.code}?',
      message: 'This permanently deletes the RFQ, its line items and attachments.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    if (await vm.delete() && context.mounted) {
      showSnack(context, '${rfq.code} deleted.');
      context.go(Routes.contractorRfqs);
    }
  }

  Future<void> _changeStatus(BuildContext context, RfqStatus s) async {
    if (s == RfqStatus.closed) {
      final ok = await confirmDialog(
        context,
        title: 'Close without hiring?',
        message: 'All pending BOQs will be rejected and suppliers can no longer respond. This cannot be undone.',
        confirmLabel: 'Close RFQ',
        destructive: true,
      );
      if (!ok) return;
    }
    await vm.changeStatus(s);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackLink(label: 'My RFQs', onTap: () => context.go(Routes.contractorRfqs)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CodeText(rfq.code, size: 13),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            rfq.title,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.place_outlined, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(rfq.deliveryLocation, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        const SizedBox(width: 16),
                        const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.textMuted),
                        const SizedBox(width: 5),
                        Text('Required by ${Fmt.date(rfq.requiredBy)}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
              if (vm.isDraft) ...[
                if (vm.canDelete)
                  TextButton.icon(
                    onPressed: vm.isBusy ? null : () => _delete(context),
                    icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                    label: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                  ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => context.go(Routes.contractorEditRfq(rfq.id)),
                  child: const Text('Edit draft'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: vm.isBusy ? null : vm.publish, child: const Text('Publish RFQ')),
              ] else ...[
                if (vm.canEdit) ...[
                  TextButton(onPressed: () => context.go(Routes.contractorEditRfq(rfq.id)), child: const Text('Edit')),
                  if (vm.canDelete)
                    TextButton(
                      onPressed: vm.isBusy ? null : () => _delete(context),
                      child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                    ),
                  const SizedBox(width: 12),
                ],
                const Text('Status', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(width: 10),
                SizedBox(
                  width: 210,
                  child: rfq.status.isFinal
                      ? Align(alignment: Alignment.centerLeft, child: RfqStatusBadge(rfq.status))
                      : AppDropdown<RfqStatus>(
                          value: rfq.status,
                          items: RfqStatus.manual,
                          labelOf: (s) => s.label,
                          dense: true,
                          onChanged: vm.isBusy ? null : (s) => s == null ? null : _changeStatus(context, s),
                        ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RevealedBanner extends StatelessWidget {
  const _RevealedBanner({required this.q});
  final ContractorQuotation q;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.greenBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.greenFg.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.handshake_outlined, color: AppColors.greenFg),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText.rich(
              TextSpan(
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                children: [
                  TextSpan(text: '${q.supplierAlias} hired. ', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const TextSpan(text: 'Supplier contact: '),
                  TextSpan(text: q.supplierCompanyName ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (q.supplierEmail != null) TextSpan(text: '  ·  ${q.supplierEmail}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.vm, required this.rfq});
  final RfqDetailViewModel vm;
  final RfqDetail rfq;

  @override
  Widget build(BuildContext context) {
    Widget row(String k, Widget v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(width: 130, child: Text(k, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
              Expanded(child: Align(alignment: Alignment.centerLeft, child: v)),
            ],
          ),
        );
    const v = TextStyle(fontSize: 13);

    return SectionCard(
      title: 'Summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((rfq.description ?? '').isNotEmpty) ...[
            Text(rfq.description!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
            const SizedBox(height: 12),
          ],
          row('Created', Text(Fmt.date(rfq.createdAt), style: v)),
          row('Line items', Text('${rfq.items.length}', style: v)),
          row('BOQs', Text('${vm.quotations.length}', style: v)),
          row('Status', RfqStatusBadge(rfq.status)),
        ],
      ),
    );
  }
}

class _Items extends StatelessWidget {
  const _Items({required this.vm, required this.rfq});
  final RfqDetailViewModel vm;
  final RfqDetail rfq;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Line items',
      padding: EdgeInsets.zero,
      child: FlexTable(
        rowHeight: 44,
        columns: const [
          FlexColumn('Item', flex: 4),
          FlexColumn('Category', flex: 3),
          FlexColumn('Specification', flex: 3),
          FlexColumn('Qty', flex: 2, align: TextAlign.right),
        ],
        rows: [
          for (final i in rfq.items)
            [
              CellText(i.itemName),
              CellText(vm.categoryName(i.categoryId), muted: true),
              CellText(i.specification ?? '—', muted: true),
              CellText('${Fmt.qty(i.quantity)} ${i.unit.label}'),
            ],
        ],
      ),
    );
  }
}

class _Attachments extends StatelessWidget {
  const _Attachments({required this.vm});
  final RfqDetailViewModel vm;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Attachments',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final a in vm.attachments)
            OutlinedButton.icon(
              icon: const Icon(Icons.download_outlined, size: 16),
              label: Text('${a.fileName}  ·  ${a.sizeLabel}'),
              onPressed: () async {
                final url = await vm.attachmentUrl(a);
                if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// BOQ cards
// ---------------------------------------------------------------------------

class _BoqCards extends StatelessWidget {
  const _BoqCards({required this.vm});
  final RfqDetailViewModel vm;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 16.0;
      final perRow = (c.maxWidth / 270).floor().clamp(1, 4);
      final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final q in vm.quotations) SizedBox(width: w, child: _BoqCard(vm: vm, q: q, best: q.id == vm.bestPriceId)),
        ],
      );
    });
  }
}

class _BoqCard extends StatelessWidget {
  const _BoqCard({required this.vm, required this.q, required this.best});
  final RfqDetailViewModel vm;
  final ContractorQuotation q;
  final bool best;

  @override
  Widget build(BuildContext context) {
    final pending = q.status.isPending && vm.canDecide;
    return SectionCard(
      highlight: best && q.status != QuotationStatus.rejected,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              QuotationStatusBadge(q.status),
              const Spacer(),
              if (best && vm.quotations.length > 1)
                const StatusPill(label: 'BEST PRICE', bg: AppColors.accent, fg: AppColors.navy, icon: Icons.emoji_events_outlined),
            ],
          ),
          const SizedBox(height: 10),
          PartyLabel(alias: q.supplierAlias, revealedName: q.isRevealed ? q.supplierCompanyName : null, fontSize: 13),
          const SizedBox(height: 8),
          Text(Fmt.aed(q.totalAmount), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Delivery: ${Fmt.date(q.deliveryDate)}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Covers '),
              TextSpan(text: '${q.coveredItems} of ${q.totalItems}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: ' items'),
            ]),
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                  onPressed: () => openContractorBoq(context, vm, q),
                  child: const Text('View BOQ', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: q.status == QuotationStatus.shortlisted ? 'Remove from shortlist' : 'Shortlist',
                onPressed: pending && !vm.isBusy ? () => vm.toggleShortlist(q) : null,
                style: IconButton.styleFrom(
                  backgroundColor: q.status == QuotationStatus.shortlisted ? AppColors.accentSoft : null,
                ),
                icon: Icon(
                  q.status == QuotationStatus.shortlisted ? Icons.star : Icons.star_border,
                  color: q.status == QuotationStatus.shortlisted ? AppColors.accent : AppColors.textSecondary,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (pending)
            ElevatedButton(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
              onPressed: vm.isBusy ? null : () => confirmHire(context, vm, q),
              child: const Text('Mark as hired', style: TextStyle(fontSize: 13)),
            )
          else
            SizedBox(
              height: 38,
              child: Center(
                child: Text(
                  q.status == QuotationStatus.accepted ? 'Hired' : (q.status == QuotationStatus.rejected ? 'Not selected' : ''),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: q.status == QuotationStatus.accepted ? AppColors.greenFg : AppColors.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> confirmHire(BuildContext context, RfqDetailViewModel vm, ContractorQuotation q) async {
  final ok = await confirmDialog(
    context,
    title: 'Hire ${q.supplierAlias}?',
    message: 'This accepts ${q.code} (${Fmt.aed(q.totalAmount)}), rejects all other BOQs for this RFQ and '
        'reveals company names and email addresses to you and this supplier.',
    confirmLabel: 'Mark as hired',
  );
  if (!ok || !context.mounted) return;
  if (await vm.accept(q) && context.mounted) {
    final c = vm.lastRevealed;
    showSnack(context, 'Supplier hired${c == null ? '' : ': ${c.companyName}'}');
  }
}

Future<void> confirmReject(BuildContext context, RfqDetailViewModel vm, ContractorQuotation q) async {
  final ok = await confirmDialog(
    context,
    title: 'Reject ${q.code}?',
    message: 'The supplier will see this BOQ as rejected.',
    confirmLabel: 'Reject',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  if (await vm.reject(q) && context.mounted) showSnack(context, '${q.code} rejected.');
}

/// Opens the itemized BOQ dialog and marks the BOQ as viewed.
Future<void> openContractorBoq(BuildContext context, RfqDetailViewModel vm, ContractorQuotation q) async {
  final rfq = vm.rfq!;
  await vm.markViewed(q);
  if (!context.mounted) return;
  final pending = q.status.isPending && vm.canDecide;
  final action = await showBoqDialog(
    context,
    title: q.code,
    lines: [
      for (final i in rfq.items)
        BoqDialogLine(
          itemName: i.itemName,
          unit: i.unit,
          line: q.lineFor(i.id),
        ),
    ],
    total: q.totalAmount,
    partyLabel: 'Supplier',
    partyAlias: q.supplierAlias,
    revealedName: q.isRevealed ? q.supplierCompanyName : null,
    revealedEmail: q.isRevealed ? q.supplierEmail : null,
    status: q.status == QuotationStatus.sent ? QuotationStatus.viewed : q.status,
    deliveryDate: q.deliveryDate,
    validUntil: q.validUntil,
    notes: q.notes,
    actions: pending ? const [BoqDialogAction.reject, BoqDialogAction.hire] : const [],
  );
  if (!context.mounted) return;
  if (action == BoqDialogAction.hire) await confirmHire(context, vm, q);
  if (action == BoqDialogAction.reject) await confirmReject(context, vm, q);
}

// ---------------------------------------------------------------------------
// Comparison table
// ---------------------------------------------------------------------------

class _Comparison extends StatelessWidget {
  const _Comparison({required this.vm, required this.rfq});
  final RfqDetailViewModel vm;
  final RfqDetail rfq;

  @override
  Widget build(BuildContext context) {
    final qs = vm.quotations;
    const head = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: AppColors.textSecondary);

    Widget cell(Widget child, {Color? bg, bool right = true}) => Container(
          color: bg,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        );

    return SectionCard(
      title: 'BOQ comparison',
      padding: EdgeInsets.zero,
      child: Table(
        columnWidths: {0: const FlexColumnWidth(2.2), for (var i = 1; i <= qs.length; i++) i: const FlexColumnWidth(1)},
        border: const TableBorder(horizontalInside: BorderSide(color: AppColors.border)),
        children: [
          TableRow(children: [
            cell(const Text('ITEM', style: head), right: false),
            for (final q in qs) cell(Text(q.shortAlias, style: head)),
          ]),
          for (final item in rfq.items)
            TableRow(children: [
              cell(
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: item.itemName),
                    TextSpan(text: ' / ${item.unit.label}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ]),
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                right: false,
              ),
              for (final q in qs) _priceCell(cell, q, item.id, vm.lowestPriceFor(item.id) == q.id),
            ]),
          TableRow(
            decoration: const BoxDecoration(color: AppColors.tableHeader),
            children: [
              cell(const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)), right: false),
              for (final q in qs)
                cell(Text(Fmt.aed(q.totalAmount), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priceCell(Widget Function(Widget, {Color? bg, bool right}) cell, ContractorQuotation q, String itemId, bool best) {
    final price = q.lineFor(itemId)?.unitPrice;
    if (price == null) return cell(const Text('—', style: TextStyle(color: AppColors.textMuted)));
    return cell(
      Text(
        Fmt.aed(price),
        style: TextStyle(
          fontSize: 13,
          fontWeight: best ? FontWeight.w700 : FontWeight.w400,
          color: best ? AppColors.greenFg : AppColors.textPrimary,
        ),
      ),
      bg: best ? AppColors.bestCell : null,
    );
  }
}
