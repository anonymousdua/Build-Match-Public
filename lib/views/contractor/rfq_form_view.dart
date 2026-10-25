import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../models/category.dart';
import '../../models/enums.dart';
import '../../viewmodels/contractor/rfq_form_view_model.dart';
import '../widgets/common.dart';
import '../widgets/file_drop_zone.dart';
import '../widgets/form_fields.dart';

/// Create RFQ / edit draft.
class RfqFormView extends StatefulWidget {
  const RfqFormView({super.key});

  @override
  State<RfqFormView> createState() => _RfqFormViewState();
}

class _RfqFormViewState extends State<RfqFormView> {
  final _formKey = GlobalKey<FormState>();

  Future<void> _save({required bool publish}) async {
    final vm = context.read<RfqFormViewModel>();
    final valid = _formKey.currentState?.validate() ?? false;
    final ok = await vm.save(publish: publish, formValid: valid);
    if (!mounted) return;
    if (!ok) {
      if (vm.actionError == null) showSnack(context, 'Please fix the highlighted fields.', error: true);
      return;
    }
    if (vm.uploadWarning != null) showSnack(context, vm.uploadWarning!, error: true);
    showSnack(context, publish ? 'RFQ published. Matched suppliers can now send BOQs.' : 'Draft saved.');
    context.go(Routes.contractorRfq(vm.savedRfqId!));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RfqFormViewModel>();

    if (vm.isLoading) return const LoadingView();
    if (vm.loadError != null) {
      return PageScaffold(children: [
        PageHeader(title: vm.isEdit ? 'Edit RFQ' : 'Create RFQ'),
        SectionCard(child: ErrorView(message: vm.loadError!, onRetry: vm.load)),
      ]);
    }

    final primaryLabel = vm.isPublished ? 'Save changes' : 'Publish RFQ';
    void primary() => _save(publish: true);
    void draft() => _save(publish: false);

    return SubmitOnEnter(
      onSubmit: vm.isPublished ? primary : draft,
      child: Form(
        key: _formKey,
        child: PageScaffold(
          maxWidth: 1180,
          children: [
            PageHeader(
              title: vm.isEdit ? 'Edit RFQ' : 'Create RFQ',
              subtitle: 'Describe what you need. Matched suppliers will reply anonymously with BOQs.',
              leading: vm.isEdit
                  ? BackLink(label: 'Back to RFQ', onTap: () => context.go(Routes.contractorRfq(vm.rfqId!)))
                  : null,
              actions: [
                if (!vm.isPublished)
                  OutlinedButton(onPressed: vm.isBusy ? null : draft, child: const Text('Save draft')),
                ElevatedButton(
                  onPressed: vm.isBusy ? null : primary,
                  child: vm.isBusy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(primaryLabel),
                ),
              ],
            ),
            if (vm.actionError != null) ErrorBanner(vm.actionError!),
            _ProjectDetails(vm: vm, onSubmit: vm.isPublished ? primary : draft),
            const SizedBox(height: 24),
            _LineItems(vm: vm, onSubmit: vm.isPublished ? primary : draft),
            const SizedBox(height: 24),
            _Attachments(vm: vm),
          ],
        ),
      ),
    );
  }
}

class _ProjectDetails extends StatelessWidget {
  const _ProjectDetails({required this.vm, required this.onSubmit});
  final RfqFormViewModel vm;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Project details',
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: LabeledField(
                  label: 'Project title',
                  child: AppTextField(
                    initialValue: vm.title,
                    hint: 'e.g. Marina tower – podium slab',
                    maxLength: AppLimits.rfqTitleMax,
                    validator: vm.validateTitle,
                    onChanged: (v) => vm.title = v,
                    onSubmitted: onSubmit,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: LabeledField(
                  label: 'Delivery location',
                  helper: 'City / region only',
                  child: AppTextField(
                    initialValue: vm.deliveryLocation,
                    hint: 'Dubai, JLT',
                    maxLength: AppLimits.locationMax,
                    validator: vm.validateLocation,
                    onChanged: (v) => vm.deliveryLocation = v,
                    onSubmitted: onSubmit,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: LabeledField(
                  label: 'Required by',
                  child: DateField(value: vm.requiredBy, onChanged: vm.setRequiredBy, errorText: vm.dateError),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LabeledField(
            label: 'Description',
            child: AppTextField(
              initialValue: vm.description,
              hint: 'Scope, standards, delivery constraints...',
              maxLines: 4,
              minLines: 3,
              maxLength: AppLimits.rfqDescriptionMax,
              validator: vm.validateDescription,
              onChanged: (v) => vm.description = v,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineItems extends StatelessWidget {
  const _LineItems({required this.vm, required this.onSubmit});
  final RfqFormViewModel vm;
  final VoidCallback onSubmit;

  static const _head = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: AppColors.textSecondary);

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Line items',
      padding: EdgeInsets.zero,
      trailing: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        onPressed: vm.addLine,
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Add row', style: TextStyle(fontSize: 13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                SizedBox(width: 32, child: Text('#', style: _head)),
                Expanded(flex: 5, child: Text('ITEM NAME', style: _head)),
                SizedBox(width: 16),
                Expanded(flex: 4, child: Text('CATEGORY', style: _head)),
                SizedBox(width: 16),
                Expanded(flex: 5, child: Text('SPECIFICATION', style: _head)),
                SizedBox(width: 16),
                SizedBox(width: 96, child: Text('QUANTITY', style: _head)),
                SizedBox(width: 16),
                SizedBox(width: 100, child: Text('UNIT', style: _head)),
                SizedBox(width: 44),
              ],
            ),
          ),
          for (var i = 0; i < vm.lines.length; i++) ...[
            const Divider(height: 1),
            _LineRow(
              key: ValueKey(vm.lines[i].key),
              index: i,
              line: vm.lines[i],
              vm: vm,
              categories: vm.categories,
              onSubmit: onSubmit,
            ),
          ],
          if (vm.lines.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No line items yet – use “Add row”.', style: TextStyle(color: AppColors.textMuted)),
            ),
          if (vm.linesError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Text(vm.linesError!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    super.key,
    required this.index,
    required this.line,
    required this.vm,
    required this.categories,
    required this.onSubmit,
  });

  final int index;
  final RfqLineDraft line;
  final RfqFormViewModel vm;
  final List<Category> categories;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Padding(padding: const EdgeInsets.only(top: 12), child: Text('${index + 1}')),
          ),
          Expanded(
            flex: 5,
            child: AppTextField(
              initialValue: line.itemName,
              hint: 'Rebar 16mm',
              maxLength: AppLimits.itemNameMax,
              validator: vm.validateItemName,
              onChanged: (v) => vm.updateLine(line.key, itemName: v),
              onSubmitted: onSubmit,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 4,
            child: AppDropdown<String>(
              value: line.categoryId,
              items: categories.map((c) => c.id).toList(),
              labelOf: (id) => categories.firstWhere((c) => c.id == id).name,
              hint: 'Select…',
              validator: (v) => v == null ? 'Required' : null,
              onChanged: (v) => vm.updateLine(line.key, categoryId: v),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 5,
            child: AppTextField(
              initialValue: line.specification,
              hint: 'Grade / size / standard',
              maxLength: AppLimits.specificationMax,
              validator: vm.validateSpecification,
              onChanged: (v) => vm.updateLine(line.key, specification: v),
              onSubmitted: onSubmit,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 96,
            child: AppTextField(
              initialValue: line.quantityText,
              numeric: true,
              maxLength: 16,
              validator: vm.validateQuantity,
              onChanged: (v) => vm.updateLine(line.key, quantityText: v),
              onSubmitted: onSubmit,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 100,
            child: AppDropdown<UnitType>(
              value: line.unit,
              items: UnitType.values,
              labelOf: (u) => u.label,
              onChanged: (u) {
                if (u != null) vm.updateLine(line.key, unit: u);
              },
            ),
          ),
          SizedBox(
            width: 44,
            child: IconButton(
              tooltip: 'Remove row',
              icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
              onPressed: () => vm.removeLine(line.key),
            ),
          ),
        ],
      ),
    );
  }
}

class _Attachments extends StatelessWidget {
  const _Attachments({required this.vm});
  final RfqFormViewModel vm;

  @override
  Widget build(BuildContext context) {
    final files = [
      for (final a in vm.existingFiles)
        _FileTile(name: a.fileName, size: a.sizeLabel, onRemove: () => vm.removeExistingFile(a)),
      for (final f in vm.pendingFiles)
        _FileTile(
          name: f.name,
          size: '${(f.bytes.length / 1024).ceil()} KB · uploads on save',
          onRemove: () => vm.removePendingFile(f),
        ),
    ];

    return SectionCard(
      title: 'Attachments (optional)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FileDropZone(
            extensions: AppConstants.attachmentExtensions,
            title: 'Drop drawings or spec sheets here, or click to browse',
            subtitle: 'PDF, DWG, XLSX up to 25 MB',
            onFiles: (picked) => vm.addFiles([for (final p in picked) PendingFile(name: p.name, bytes: p.bytes)]),
          ),
          if (vm.fileError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(vm.fileError!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
          if (files.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...files,
          ],
          const SizedBox(height: 10),
          const Text(
            'Tip: matched suppliers can download attachments. Remove company names and logos from drawings to stay anonymous.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.name, required this.size, required this.onRemove});
  final String name;
  final String size;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
          Text(size, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close, size: 16),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
