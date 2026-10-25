import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/input_sanitizer.dart';
import '../../models/enums.dart';
import '../../viewmodels/session_view_model.dart';
import '../widgets/brand.dart';

class _NavItem {
  const _NavItem(this.label, this.icon, this.route, {this.exact = false});
  final String label;
  final IconData icon;
  final String route;
  final bool exact;
}

const _contractorNav = [
  _NavItem('Dashboard', Icons.grid_view_outlined, Routes.contractor, exact: true),
  _NavItem('My RFQs', Icons.description_outlined, Routes.contractorRfqs),
  _NavItem('Create RFQ', Icons.note_add_outlined, Routes.contractorNewRfq, exact: true),
  _NavItem('Settings', Icons.settings_outlined, Routes.contractorSettings),
];

const _supplierNav = [
  _NavItem('Dashboard', Icons.grid_view_outlined, Routes.supplier, exact: true),
  _NavItem('My Products', Icons.inventory_2_outlined, Routes.supplierProducts),
  _NavItem('Add Product', Icons.add_box_outlined, Routes.supplierNewProduct, exact: true),
  _NavItem('Matched RFQs', Icons.track_changes, Routes.supplierMatched),
  _NavItem('My BOQs', Icons.send_outlined, Routes.supplierBoqs),
  _NavItem('Settings', Icons.settings_outlined, Routes.supplierSettings),
];

/// Fixed sidebar + top bar around every signed-in page.
/// (No notification bell – removed from the designs on purpose.)
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _searchFocus = FocusNode();
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchFocus.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _search(UserRole role) {
    final q = InputSanitizer.clean(_searchCtrl.text);
    final base = role == UserRole.contractor ? Routes.contractorRfqs : Routes.supplierMatched;
    context.go(q.isEmpty ? base : Uri(path: base, queryParameters: {'q': q}).toString());
    _searchCtrl.clear();
    _searchFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionViewModel>();
    final profile = session.profile;
    if (profile == null) return const Scaffold(body: SizedBox.shrink());
    final nav = profile.role == UserRole.contractor ? _contractorNav : _supplierNav;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => _searchFocus.requestFocus(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              _Sidebar(
                items: nav,
                location: widget.location,
                roleLabel: profile.role.label,
                shortAlias: profile.shortAlias,
              ),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      searchCtrl: _searchCtrl,
                      searchFocus: _searchFocus,
                      onSearch: () => _search(profile.role),
                      alias: profile.alias,
                      email: session.email ?? '',
                      initial: profile.role == UserRole.contractor ? 'C' : 'S',
                      onSettings: () => context.go(
                        profile.role == UserRole.contractor ? Routes.contractorSettings : Routes.supplierSettings,
                      ),
                      onLogout: () => session.signOut(),
                    ),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.items, required this.location, required this.roleLabel, required this.shortAlias});
  final List<_NavItem> items;
  final String location;
  final String roleLabel;
  final String shortAlias;

  bool _isActive(_NavItem item) {
    if (item.exact) return location == item.route;
    // "My RFQs" stays active on RFQ detail pages but not on "Create RFQ"
    final other = items.where((i) => i != item && i.exact && i.route != items.first.route).map((i) => i.route);
    if (other.contains(location)) return false;
    return location == item.route || location.startsWith('${item.route}/');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      color: AppColors.navy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 22, 20, 18), child: BrandLogo()),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.navyLight, borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Signed in as $roleLabel', style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 12)),
                const SizedBox(height: 2),
                Text(shortAlias, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final item in items) _NavTile(item: item, active: _isActive(item)),
          const Spacer(),
          const Divider(color: Color(0x22FFFFFF), height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Text(AppConstants.version, style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.active});
  final _NavItem item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.navy : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: active ? AppColors.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          onTap: () => context.go(item.route),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(item.icon, size: 18, color: fg),
                const SizedBox(width: 12),
                Text(item.label, style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.searchCtrl,
    required this.searchFocus,
    required this.onSearch,
    required this.alias,
    required this.email,
    required this.initial,
    required this.onSettings,
    required this.onLogout,
  });

  final TextEditingController searchCtrl;
  final FocusNode searchFocus;
  final VoidCallback onSearch;
  final String alias;
  final String email;
  final String initial;
  final VoidCallback onSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 384,
            child: TextField(
              controller: searchCtrl,
              focusNode: searchFocus,
              onSubmitted: (_) => onSearch(),
              inputFormatters: [LengthLimitingTextInputFormatter(100)],
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search RFQs, BOQs, products...',
                fillColor: AppColors.background,
                prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textMuted),
                prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 20),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.borderStrong),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Ctrl K', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                  ),
                ),
                suffixIconConstraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              ),
            ),
          ),
          const Spacer(),
          _AccountMenu(alias: alias, email: email, initial: initial, onSettings: onSettings, onLogout: onLogout),
        ],
      ),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({
    required this.alias,
    required this.email,
    required this.initial,
    required this.onSettings,
    required this.onLogout,
  });

  final String alias;
  final String email;
  final String initial;
  final VoidCallback onSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'My account',
      offset: const Offset(0, 52),
      onSelected: (v) => v == 'settings' ? onSettings() : onLogout(),
      itemBuilder: (ctx) => const [
        PopupMenuItem<String>(
          enabled: false,
          height: 36,
          child: Text('My account', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ),
        PopupMenuItem<String>(
          value: 'settings',
          height: 40,
          child: Row(children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 10), Text('Settings')]),
        ),
        PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'logout',
          height: 40,
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: AppColors.danger),
              SizedBox(width: 10),
              Text('Log out', style: TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.primary,
              child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(alias, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                Text(email, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
