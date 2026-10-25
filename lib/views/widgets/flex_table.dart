import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Column definition for [FlexTable].
class FlexColumn {
  const FlexColumn(this.label, {this.flex = 1, this.align = TextAlign.left, this.onSort, this.sorted, this.width});
  final String label;
  final int flex;
  final double? width; // fixed width instead of flex
  final TextAlign align;
  final VoidCallback? onSort;

  /// null = not the sort column; true = ascending; false = descending.
  final bool? sorted;
}

/// Lightweight table matching the design (uppercase grey headers, row
/// dividers, hover). Cells are widgets so rows can hold badges/buttons.
class FlexTable extends StatelessWidget {
  const FlexTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.rowHeight = 52,
    this.headerColor,
    this.highlightRow,
  });

  final List<FlexColumn> columns;
  final List<List<Widget>> rows;
  final void Function(int index)? onRowTap;
  final double rowHeight;
  final Color? headerColor;
  final bool Function(int index)? highlightRow;

  Widget _cell(FlexColumn c, Widget child) {
    final aligned = Align(
      alignment: switch (c.align) {
        TextAlign.right || TextAlign.end => Alignment.centerRight,
        TextAlign.center => Alignment.center,
        _ => Alignment.centerLeft,
      },
      child: child,
    );
    final padded = Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: aligned);
    return c.width != null ? SizedBox(width: c.width, child: padded) : Expanded(flex: c.flex, child: padded);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: headerColor,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              for (final c in columns)
                _cell(
                  c,
                  InkWell(
                    onTap: c.onSort,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c.label.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (c.onSort != null) ...[
                          const SizedBox(width: 4),
                          Icon(
                            c.sorted == null
                                ? Icons.unfold_more
                                : (c.sorted! ? Icons.arrow_upward : Icons.arrow_downward),
                            size: 12,
                            color: c.sorted == null ? AppColors.textMuted : AppColors.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (var i = 0; i < rows.length; i++) ...[
          const Divider(height: 1),
          Material(
            color: (highlightRow?.call(i) ?? false) ? AppColors.accentSoft : Colors.white,
            child: InkWell(
              onTap: onRowTap == null ? null : () => onRowTap!(i),
              hoverColor: AppColors.tableHeader,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: rowHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    children: [for (var c = 0; c < columns.length; c++) _cell(columns[c], rows[i][c])],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Default text style for a table cell.
class CellText extends StatelessWidget {
  const CellText(this.text, {super.key, this.muted = false, this.bold = false, this.align});
  final String text;
  final bool muted;
  final bool bold;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: align,
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
        style: TextStyle(
          fontSize: 14,
          color: muted ? AppColors.textSecondary : AppColors.textPrimary,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        ),
      );
}
