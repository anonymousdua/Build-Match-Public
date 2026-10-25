import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/enums.dart';
import '../../models/matched_rfq.dart';
import '../../models/product.dart';
import '../../viewmodels/session_view_model.dart';
import '../../viewmodels/supplier/create_boq_view_model.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

/// RFQ detail for a supplier + "Your quotation" form.
class CreateBoqView extends StatefulWidget {
  const CreateBoqView({super.key});

  @override
  State<CreateBoqView> createState() => _CreateBoqViewState();
}

class _CreateBoqViewState extends State<CreateBoqView> {
  final _formKey = GlobalKey<FormState>();

  Future<void> _save({required bool send}) async {
    final vm = context.read<CreateBoqViewModel>();
    if (send) {
      final ok = await confirmDialog(
        context,
        title: 'Send BOQ?',
        message: 'You are quoting ${vm.suppliedCount} of ${vm.lines.length} items for ${Fmt.aed(vm.grandTotal)}. '
            'A sent BOQ cannot be edited.',
        confirmLabel: 'Send BOQ',
      );
      if (!ok || !mounted) return;
    }
    final valid = _formKey.currentState?.validate() ?? false;
    final ok = await vm.save(send: send, formValid: valid);
    if (!mounted || !ok) return;
    showSnack(context, send ? 'BOQ sent. The contractor will see it under your alias.' : 'Draft saved.');
    if (send) context.go(Routes.supplierBoqs);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CreateBoqViewModel>();
    final myAlias = context.select<SessionViewModel, String>((s) => s.profile?.alias ?? '');
    final rfq = vm.rfq;

    if (vm.isLoading && rfq == null) return const LoadingView();
    if (rfq == null) {
      return PageScaffold(children: [
        BackLink(label: 'Matched RFQs', onTap: () => context.go(Routes.supplierMatched)),
        const SizedBox(height: 16),
        SectionCard(
          child: vm.loadError != null
              ? ErrorView(message: vm.loadError!, onRetry: vm.load)
              : const EmptyView(
                  icon: Icons.lock_outline,
                  title: 'RFQ not available',
                  message: 'This RFQ does not exist or is not matched to your catalog.',
                ),
        ),
      ]);
    }

    final readOnly = vm.readOnly;
    final q = rfq.myQuotation;

    return SubmitOnEnter(
      onSubmit: () {
        if (!readOnly) _save(send: false);
      },
      child: Form(
        key: _formKey,
        child: PageScaffold(
          children: [
            PageHeader(
              title: q != null && q.status != QuotationStatus.draft ? 'BOQ ${q.code}' : 'Create BOQ',
              leading: BackLink(label: 'Matched RFQs', onTap: () => context.go(Routes.supplierMatched)),
              actions: readOnly
                  ? const []
                  : [
                      OutlinedButton(onPressed: vm.isBusy ? null : () => _save(send: false), child: const Text('Save draft')),
                      ElevatedButton(
                        onPressed: vm.isBusy ? null : () => _save(send: true),
                        child: vm.isBusy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Send BOQ'),
                      ),
                    ],
            ),
            Transform.translate(
              offset: const Offset(0, -16),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  const Text('Responding to', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  CodeText(rfq.rfqCode, color: AppColors.textSecondary),
                  const Text('as', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  Text(myAlias, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const IdentityHiddenChip(),
                ],
              ),
            ),
            if (vm.readOnlyReason != null) InfoBanner(vm.readOnlyReason!, icon: Icons.lock_outline),
            if (rfq.revealedContact != null)
              InfoBanner(
                'Your BOQ was accepted. Contractor contact: ${rfq.revealedContact!.companyName}'
                '${rfq.revealedContact!.email == null ? '' : ' · ${rfq.revealedContact!.email}'}',
                icon: Icons.handshake_outlined,
              ),
            if (vm.actionError != null) ErrorBanner(vm.actionError!),
            if (vm.formError != null) ErrorBanner(vm.formError!),
            LayoutBuilder(builder: (context, c) {
              final quote = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Quotation(vm: vm, readOnly: readOnly),
                  const SizedBox(height: 22),
                  _Terms(vm: vm, readOnly: readOnly),
                ],
              );
              // Wide screens: details beside the quote (as in the design).
              // Narrower windows: details on top so the quote table has room.
              if (c.maxWidth >= 1400) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 320, child: _RfqDetails(vm: vm, rfq: rfq)),
                    const SizedBox(width: 22),
                    Expanded(child: quote),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_RfqDetails(vm: vm, rfq: rfq), const SizedBox(height: 22), quote],
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _RfqDetails extends StatelessWidget {
  const _RfqDetails({required this.vm, required this.rfq});
  final CreateBoqViewModel vm;
  final SupplierRfq rfq;

  @override
  Widget build(BuildContext context) {
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(width: 110, child: Text(k, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
              Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
            ],
          ),
        );

    return SectionCard(
      title: 'RFQ details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(rfq.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          PartyLabel(alias: rfq.contractorAlias, revealedName: rfq.revealedContact?.companyName, fontSize: 13, bold: true),
          if ((rfq.description ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(rfq.description!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.45)),
          ],
          const SizedBox(height: 14),
          kv('Location', rfq.deliveryLocation),
          kv('Required by', Fmt.date(rfq.requiredBy)),
          kv('Match', Fmt.percent(rfq.matchScore)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: [
                for (var i = 0; i < rfq.items.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(rfq.items[i].itemName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                              if (rfq.items[i].specification != null)
                                Text(rfq.items[i].specification!, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        Text('${Fmt.qty(rfq.items[i].quantity)} ${rfq.items[i].unit.label}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (vm.attachments.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Attachments', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
            const SizedBox(height: 6),
            for (final a in vm.attachments)
              TextButton.icon(
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                icon: const Icon(Icons.download_outlined, size: 16),
                label: Text(a.fileName, overflow: TextOverflow.ellipsis),
                onPressed: () async {
                  final url = await vm.attachmentUrl(a);
                  if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _Quotation extends StatelessWidget {
  const _Quotation({required this.vm, required this.readOnly});
  final CreateBoqViewModel vm;
  final bool readOnly;

  static const _head = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: AppColors.textSecondary);

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Your quotation',
      padding: EdgeInsets.zero,
      child: LayoutBuilder(builder: (context, c) {
        const minWidth = 940.0;
        final table = _table();
        if (c.maxWidth >= minWidth) return table;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: minWidth, child: table),
        );
      }),
    );
  }

  Widget _table() {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: Row(
              children: [
                Expanded(flex: 4, child: Text('REQUESTED ITEM', style: _head)),
                SizedBox(width: 12),
                Expanded(flex: 5, child: Text('YOUR PRODUCT', style: _head)),
                SizedBox(width: 12),
                SizedBox(width: 80, child: Text('QTY', style: _head)),
                SizedBox(width: 12),
                SizedBox(width: 92, child: Text('UNIT PRICE', style: _head)),
                SizedBox(width: 12),
                SizedBox(width: 112, child: Text('AVAILABILITY', style: _head)),
                SizedBox(width: 12),
                SizedBox(width: 100, child: Text('LINE TOTAL', style: _head, textAlign: TextAlign.right)),
                SizedBox(width: 12),
                SizedBox(width: 140, child: Text('DELIVERY', style: _head)),
              ],
            ),
          ),
          for (final l in vm.lines) ...[
            const Divider(height: 1),
            _BoqRow(key: ValueKey(l.item.id), vm: vm, line: l, readOnly: readOnly),
          ],
          const Divider(height: 1),
          Container(
            color: AppColors.tableHeader,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Text('Grand total · ${vm.suppliedCount} of ${vm.lines.length} items',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(Fmt.aed(vm.grandTotal), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(width: 152),
              ],
            ),
          ),
        ],
      );
  }
}

class _BoqRow extends StatelessWidget {
  const _BoqRow({super.key, required this.vm, required this.line, required this.readOnly});
  final CreateBoqViewModel vm;
  final BoqLineDraft line;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final options = vm.productOptionsFor(line.item);
    final editable = !readOnly && line.isSupplied;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.item.itemName, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                  Text('${Fmt.qty(line.item.quantity)} ${line.item.unit.label}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: AppDropdown<Product?>(
              value: options.where((p) => p.id == line.productId).firstOrNull,
              items: [null, ...options],
              labelOf: (p) => p == null
                  ? 'Not supplied'
                  : '${p.name}${line.item.suggestedProductIds.contains(p.id) ? '  ★' : ''}',
              dense: true,
              onChanged: readOnly ? null : (p) => vm.selectProduct(line, p?.id),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: AppTextField(
              key: ValueKey('q-${line.item.id}-${line.isSupplied}'),
              initialValue: line.quantityText,
              numeric: true,
              maxLength: 16,
              enabled: editable,
              validator: (v) => vm.validateQuantity(line, v),
              onChanged: (v) => vm.setQuantity(line, v),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: AppTextField(
              key: ValueKey('p-${line.item.id}-${line.isSupplied}'),
              initialValue: line.unitPriceText,
              numeric: true,
              maxLength: 14,
              enabled: editable,
              validator: (v) => vm.validateUnitPrice(line, v),
              onChanged: (v) => vm.setUnitPrice(line, v),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 112,
            child: AppDropdown<Availability>(
              value: line.availability,
              items: Availability.values,
              labelOf: (a) => a.label,
              dense: true,
              onChanged: editable
                  ? (a) {
                      if (a != null) vm.setAvailability(line, a);
                    }
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                line.lineTotal == null ? '—' : Fmt.aed(line.lineTotal),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: DateField(
              value: line.isSupplied ? line.deliveryDate : null,
              placeholder: Fmt.date(vm.rfq?.requiredBy),
              dense: true,
              enabled: editable,
              onChanged: (d) => vm.setLineDelivery(line, d),
            ),
          ),
        ],
      ),
    );
  }
}

class _Terms extends StatelessWidget {
  const _Terms({required this.vm, required this.readOnly});
  final CreateBoqViewModel vm;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Terms',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: LabeledField(
              label: 'Valid until',
              child: DateField(value: vm.validUntil, onChanged: vm.setValidUntil, enabled: !readOnly),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: LabeledField(
              label: 'Notes',
              child: AppTextField(
                initialValue: vm.notes,
                hint: 'Payment terms, delivery conditions, certificates...',
                maxLines: 3,
                minLines: 2,
                readOnly: readOnly,
                maxLength: AppLimits.notesMax,
                validator: vm.validateNotes,
                onChanged: (v) => vm.notes = v,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
