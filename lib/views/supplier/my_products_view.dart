import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../viewmodels/supplier/my_products_view_model.dart';
import '../widgets/common.dart';
import '../widgets/flex_table.dart';
import '../widgets/form_fields.dart';

class MyProductsView extends StatelessWidget {
  const MyProductsView({super.key});

  Future<void> _delete(BuildContext context, MyProductsViewModel vm, Product p) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete ${p.name}?',
      message: 'It will no longer be matched to new RFQs. BOQs you already sent are not affected.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    if (await vm.delete(p) && context.mounted) showSnack(context, '${p.name} deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MyProductsViewModel>();
    final rows = vm.visible;
    bool? sorted(ProductSortField f) => vm.sortField == f ? vm.ascending : null;

    return PageScaffold(
      children: [
        PageHeader(
          title: 'My Products',
          subtitle: 'Your catalog is used to match you with contractor RFQs.',
          actions: [
            ElevatedButton.icon(
              onPressed: () => context.go(Routes.supplierNewProduct),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add product'),
            ),
          ],
        ),
        if (vm.actionError != null) ErrorBanner(vm.actionError!),
        SectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    SearchField(hint: 'Search products', initialValue: vm.query, onChanged: vm.setQuery),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 224,
                      child: AppDropdown<Category?>(
                        value: vm.categories.where((c) => c.id == vm.categoryFilter).firstOrNull,
                        items: [null, ...vm.categories],
                        labelOf: (c) => c?.name ?? 'All categories',
                        onChanged: (c) => vm.setCategoryFilter(c?.id),
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
                  icon: Icons.inventory_2_outlined,
                  title: 'Your catalog is empty',
                  message: 'Add the products you can supply. Contractor RFQs are matched against them automatically.',
                  action: ElevatedButton(
                    onPressed: () => context.go(Routes.supplierNewProduct),
                    child: const Text('Add product'),
                  ),
                )
              else if (rows.isEmpty)
                const EmptyView(icon: Icons.search_off, title: 'No products match your filters')
              else
                FlexTable(
                  rowHeight: 56,
                  columns: [
                    FlexColumn('Product', flex: 5, onSort: () => vm.sortBy(ProductSortField.name), sorted: sorted(ProductSortField.name)),
                    FlexColumn('Category', flex: 4, onSort: () => vm.sortBy(ProductSortField.category), sorted: sorted(ProductSortField.category)),
                    const FlexColumn('Unit', flex: 2),
                    FlexColumn('Available', flex: 3, align: TextAlign.right, onSort: () => vm.sortBy(ProductSortField.available), sorted: sorted(ProductSortField.available)),
                    FlexColumn('Price range', flex: 4, align: TextAlign.right, onSort: () => vm.sortBy(ProductSortField.price), sorted: sorted(ProductSortField.price)),
                    FlexColumn('Lead time', flex: 3, onSort: () => vm.sortBy(ProductSortField.leadTime), sorted: sorted(ProductSortField.leadTime)),
                    const FlexColumn('Actions', flex: 2, align: TextAlign.right),
                  ],
                  rows: [
                    for (final p in rows)
                      [
                        Row(
                          children: [
                            Flexible(child: CellText(p.name, bold: false)),
                            if (!p.isActive) ...[
                              const SizedBox(width: 8),
                              const StatusPill(label: 'Unavailable', bg: AppColors.greyBg, fg: AppColors.greyFg, dot: false),
                            ],
                          ],
                        ),
                        TagChip(vm.categoryName(p.categoryId)),
                        CellText(p.unit.label, muted: true),
                        CellText(Fmt.qty(p.availableQuantity)),
                        CellText(Fmt.aedRange(p.priceMin, p.priceMax)),
                        CellText(p.leadTimeDays == null ? '—' : '${p.leadTimeDays} days', muted: true),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => context.go(Routes.supplierEditProduct(p.id)),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                              onPressed: vm.isBusy ? null : () => _delete(context, vm, p),
                            ),
                          ],
                        ),
                      ],
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
