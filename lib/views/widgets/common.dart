import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/enums.dart';

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

/// Scrollable page body with the standard padding and max width.
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.children, this.maxWidth});
  final List<Widget> children;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 48),
      child: maxWidth == null
          ? content
          : Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth!), child: content),
            ),
    );
  }
}

/// "Title / subtitle ............ [actions]"
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const [], this.leading, this.titleWidget});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading; // e.g. back link
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null) ...[leading!, const SizedBox(height: 10)],
                titleWidget ??
                    Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.4)),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(subtitle!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 16),
            Wrap(spacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}

/// "← My RFQs"
class BackLink extends StatelessWidget {
  const BackLink({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_back, size: 15, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// White card with an optional titled header and divider.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.highlight = false,
  });

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: highlight ? AppColors.accent : AppColors.border, width: highlight ? 1.5 : 1),
        boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 6, offset: Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  Expanded(child: Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon, this.caption});
  final String label;
  final String value;
  final IconData icon;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: SizedBox(
        height: 104,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14))),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: AppColors.iconTile, borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 18, color: AppColors.primary),
                ),
              ],
            ),
            const Spacer(),
            Text(value, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600, height: 1)),
            const SizedBox(height: 8),
            Text(caption ?? '', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Row of equally sized stat cards.
class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.cards});
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Badges / chips
// ---------------------------------------------------------------------------

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.bg, required this.fg, this.dot = true, this.icon});
  final String label;
  final Color bg;
  final Color fg;
  final bool dot;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: fg), const SizedBox(width: 4)],
          if (dot && icon == null) ...[
            Container(width: 5, height: 5, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class RfqStatusBadge extends StatelessWidget {
  const RfqStatusBadge(this.status, {super.key});
  final RfqStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      RfqStatus.open || RfqStatus.boqsReceived => (AppColors.blueBg, AppColors.blueFg),
      RfqStatus.underReview => (AppColors.amberBg, AppColors.amberFg),
      RfqStatus.hired => (AppColors.greenBg, AppColors.greenFg),
      RfqStatus.closed || RfqStatus.draft => (AppColors.greyBg, AppColors.greyFg),
    };
    return StatusPill(label: status.label, bg: bg, fg: fg);
  }
}

class QuotationStatusBadge extends StatelessWidget {
  const QuotationStatusBadge(this.status, {super.key});
  final QuotationStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      QuotationStatus.sent || QuotationStatus.viewed => (AppColors.blueBg, AppColors.blueFg),
      QuotationStatus.shortlisted => (AppColors.amberBg, AppColors.amberFg),
      QuotationStatus.accepted => (AppColors.greenBg, AppColors.greenFg),
      QuotationStatus.rejected => (AppColors.redBg, AppColors.redFg),
      QuotationStatus.draft => (AppColors.greyBg, AppColors.greyFg),
    };
    return StatusPill(label: status.label, bg: bg, fg: fg);
  }
}

/// Small yellow "🔒 IDENTITY HIDDEN" chip.
class IdentityHiddenChip extends StatelessWidget {
  const IdentityHiddenChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(999)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 11, color: AppColors.amberFg),
          SizedBox(width: 3),
          Text(
            'IDENTITY HIDDEN',
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: AppColors.amberFg),
          ),
        ],
      ),
    );
  }
}

/// Green "✓ REVEALED" chip shown once a BOQ was accepted.
class RevealedChip extends StatelessWidget {
  const RevealedChip({super.key});

  @override
  Widget build(BuildContext context) {
    return const StatusPill(label: 'IDENTITY REVEALED', bg: AppColors.greenBg, fg: AppColors.greenFg, icon: Icons.lock_open);
  }
}

/// "94%" match badge – green ≥ 85, amber below.
class MatchBadge extends StatelessWidget {
  const MatchBadge(this.score, {super.key});
  final double score;

  @override
  Widget build(BuildContext context) {
    final strong = score >= 85;
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: strong ? AppColors.greenBg : AppColors.amberBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        Fmt.percent(score),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: strong ? AppColors.greenFg : AppColors.amberFg),
      ),
    );
  }
}

/// Grey category tag ("Steel & Rebar").
class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.greyBg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
    );
  }
}

/// Monospace code text: RFQ-2041
class CodeText extends StatelessWidget {
  const CodeText(this.text, {super.key, this.size = 12, this.color = AppColors.primary});
  final String text;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(text, style: AppTheme.code(size: size, color: color));
}

/// Alias + identity chip, or revealed company name.
class PartyLabel extends StatelessWidget {
  const PartyLabel({super.key, required this.alias, this.revealedName, this.fontSize = 14, this.bold = false});
  final String alias;
  final String? revealedName;
  final double fontSize;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: fontSize, fontWeight: bold ? FontWeight.w600 : FontWeight.w400);
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(revealedName ?? alias, style: style),
        if (revealedName == null) const IdentityHiddenChip() else const RevealedChip(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.padding = 48});
  final double padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.all(padding),
        child: const Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5))),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: AppColors.redBg, shape: BoxShape.circle),
              child: const Icon(Icons.error_outline, color: AppColors.redFg, size: 22),
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 16), label: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.title, this.message, this.icon = Icons.inbox_outlined, this.action});
  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: AppColors.greyBg, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.textMuted, size: 20),
            ),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            if (message != null) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Red inline error banner for form/action errors.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.redBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.redFg.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.redFg),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: AppColors.redFg, fontSize: 13))),
        ],
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner(this.message, {super.key, this.icon = Icons.info_outline});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppColors.blueBg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.blueFg),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: AppColors.blueFg, fontSize: 13))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feedback helpers
// ---------------------------------------------------------------------------

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.redFg : AppColors.textPrimary,
    ));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(message)),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        ElevatedButton(
          autofocus: true,
          style: destructive ? ElevatedButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
