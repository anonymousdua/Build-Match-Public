import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/matched_rfq.dart';
import '../widgets/common.dart';

/// "Send BOQ" / "Continue BOQ" / "BOQ sent" button for a matched RFQ.
class BoqActionButton extends StatelessWidget {
  const BoqActionButton({super.key, required this.m});
  final MatchedRfq m;

  @override
  Widget build(BuildContext context) {
    void open() => context.go(Routes.supplierRfq(m.rfqId));
    const pad = EdgeInsets.symmetric(horizontal: 12, vertical: 10);

    if (m.hasSentBoq || !m.rfqStatus.isActive) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(padding: pad, foregroundColor: AppColors.textMuted),
        onPressed: open,
        child: Text(m.hasSentBoq ? 'BOQ sent' : 'Closed', style: const TextStyle(fontSize: 12)),
      );
    }
    return ElevatedButton(
      style: ElevatedButton.styleFrom(padding: pad),
      onPressed: open,
      child: Text(m.hasDraftBoq ? 'Continue BOQ' : 'Send BOQ', style: const TextStyle(fontSize: 12)),
    );
  }
}

/// Dashboard list row.
class MatchedRfqTile extends StatelessWidget {
  const MatchedRfqTile({super.key, required this.m});
  final MatchedRfq m;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go(Routes.supplierRfq(m.rfqId)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            MatchBadge(m.matchScore),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      Text(m.contractorAlias, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const IdentityHiddenChip(),
                      Text(
                        '· ${m.deliveryLocation} · needed by ${Fmt.date(m.requiredBy)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            BoqActionButton(m: m),
          ],
        ),
      ),
    );
  }
}
