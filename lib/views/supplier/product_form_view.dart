import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../viewmodels/supplier/product_form_view_model.dart';
import '../widgets/common.dart';
import '../widgets/file_drop_zone.dart';
import '../widgets/form_fields.dart';

/// Add product / Edit product.
class ProductFormView extends StatefulWidget {
  const ProductFormView({super.key});

  @override
  State<ProductFormView> createState() => _ProductFormViewState();
}

class _ProductFormViewState extends State<ProductFormView> {
  final _formKey = GlobalKey<FormState>();

  Future<void> _save() async {
    final vm = context.read<ProductFormViewModel>();
    final valid = _formKey.currentState?.validate() ?? false;
    final ok = await vm.save(formValid: valid);
    if (!mounted) return;
    if (ok) {
      showSnack(context, vm.isEdit ? 'Product updated.' : 'Product added – matching against open RFQs.');
      context.go(Routes.supplierProducts);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProductFormViewModel>();
    if (vm.isLoading) return const LoadingView();
    if (vm.loadError != null) {
      return PageScaffold(children: [
        PageHeader(title: vm.isEdit ? 'Edit product' : 'Add product'),
        SectionCard(child: ErrorView(message: vm.loadError!, onRetry: vm.load)),
      ]);
    }

    return SubmitOnEnter(
      onSubmit: _save,
      child: Form(
        key: _formKey,
        child: PageScaffold(
          maxWidth: 1040,
          children: [
            PageHeader(
              title: vm.isEdit ? 'Edit product' : 'Add product',
              subtitle: 'Products are matched against incoming RFQs.',
              actions: [
                OutlinedButton(onPressed: () => context.go(Routes.supplierProducts), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: vm.isBusy ? null : _save,
                  child: vm.isBusy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save product'),
                ),
              ],
            ),
            if (vm.actionError != null) ErrorBanner(vm.actionError!),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: _Info(vm: vm, onSubmit: _save)),
                const SizedBox(width: 24),
                Expanded(flex: 3, child: _Image(vm: vm)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.vm, required this.onSubmit});
  final ProductFormViewModel vm;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    Widget pair(Widget a, Widget b) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Expanded(child: a), const SizedBox(width: 16), Expanded(child: b)],
        );

    return SectionCard(
      title: 'Product information',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          pair(
            LabeledField(
              label: 'Product name',
              child: AppTextField(
                initialValue: vm.name,
                hint: 'e.g. Rebar B500B (8–32mm)',
                maxLength: AppLimits.productNameMax,
                validator: vm.validateName,
                onChanged: (v) => vm.name = v,
                onSubmitted: onSubmit,
              ),
            ),
            LabeledField(
              label: 'Category',
              child: AppDropdown<String>(
                value: vm.categoryId,
                items: vm.categories.map((c) => c.id).toList(),
                labelOf: (id) => vm.categories.firstWhere((c) => c.id == id).name,
                hint: 'Select...',
                errorText: vm.categoryError,
                onChanged: vm.setCategory,
              ),
            ),
          ),
          const SizedBox(height: 18),
          LabeledField(
            label: 'Description',
            child: AppTextField(
              initialValue: vm.description,
              maxLines: 3,
              minLines: 3,
              maxLength: AppLimits.productDescriptionMax,
              validator: vm.validateDescription,
              onChanged: (v) => vm.description = v,
            ),
          ),
          const SizedBox(height: 18),
          LabeledField(
            label: 'Specifications',
            helper: 'Grades, sizes, standards',
            child: AppTextField(
              initialValue: vm.specifications,
              maxLines: 3,
              minLines: 2,
              maxLength: AppLimits.productSpecsMax,
              validator: vm.validateSpecs,
              onChanged: (v) => vm.specifications = v,
            ),
          ),
          const SizedBox(height: 18),
          pair(
            LabeledField(
              label: 'Unit',
              child: AppDropdown<UnitType>(
                value: vm.unit,
                items: UnitType.values,
                labelOf: (u) => u.label,
                onChanged: (u) {
                  if (u != null) vm.setUnit(u);
                },
              ),
            ),
            LabeledField(
              label: 'Available quantity',
              child: AppTextField(
                initialValue: vm.availableText,
                numeric: true,
                maxLength: 16,
                validator: vm.validateAvailable,
                onChanged: (v) => vm.availableText = v,
                onSubmitted: onSubmit,
              ),
            ),
          ),
          const SizedBox(height: 18),
          pair(
            LabeledField(
              label: 'Base price (AED / unit)',
              child: AppTextField(
                initialValue: vm.priceMinText,
                numeric: true,
                maxLength: 14,
                validator: vm.validatePriceMin,
                onChanged: (v) => vm.priceMinText = v,
                onSubmitted: onSubmit,
              ),
            ),
            LabeledField(
              label: 'Max price (optional)',
              helper: 'Leave empty for a single price',
              child: AppTextField(
                initialValue: vm.priceMaxText,
                numeric: true,
                maxLength: 14,
                validator: vm.validatePriceMax,
                onChanged: (v) => vm.priceMaxText = v,
                onSubmitted: onSubmit,
              ),
            ),
          ),
          const SizedBox(height: 18),
          pair(
            LabeledField(
              label: 'Lead time (days)',
              child: AppTextField(
                initialValue: vm.leadTimeText,
                numeric: true,
                maxLength: 3,
                validator: vm.validateLeadTime,
                onChanged: (v) => vm.leadTimeText = v,
                onSubmitted: onSubmit,
              ),
            ),
            LabeledField(
              label: 'Availability',
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.borderStrong),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        vm.isActive ? 'Available – matched to RFQs' : 'Unavailable – not matched',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    Switch(value: vm.isActive, onChanged: vm.setActive),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Image extends StatelessWidget {
  const _Image({required this.vm});
  final ProductFormViewModel vm;

  @override
  Widget build(BuildContext context) {
    Widget? preview;
    if (vm.newImageBytes != null) {
      preview = Image.memory(vm.newImageBytes!, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    } else if (vm.imageUrl != null) {
      preview = Image.network(
        vm.imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted)),
      );
    }

    return SectionCard(
      title: 'Product image',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FileDropZone(
            height: 280,
            multiple: false,
            icon: Icons.add_photo_alternate_outlined,
            title: 'Upload image',
            subtitle: 'PNG or JPG',
            extensions: AppConstants.imageExtensions,
            onFiles: (f) => vm.setImage(f.first.name, f.first.bytes),
            child: preview == null ? null : ClipRRect(borderRadius: BorderRadius.circular(10), child: preview),
          ),
          if (vm.imageError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(vm.imageError!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
          if (vm.hasImage)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: vm.removeImage, child: const Text('Remove image')),
            ),
        ],
      ),
    );
  }
}
