import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../viewmodels/settings_view_model.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

/// Settings → Account. (Notification preferences removed by request.)
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  late final TextEditingController _company;

  @override
  void initState() {
    super.initState();
    final vm = context.read<SettingsViewModel>();
    _email = TextEditingController(text: vm.email);
    _company = TextEditingController(text: vm.companyName);
  }

  @override
  void dispose() {
    _email.dispose();
    _company.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final vm = context.read<SettingsViewModel>();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await vm.save(email: _email.text, companyName: _company.text);
    if (ok && mounted && vm.info != null) showSnack(context, vm.info!);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    return Form(
      key: _formKey,
      child: PageScaffold(
        maxWidth: 780,
        children: [
          const PageHeader(title: 'Settings', subtitle: 'Manage your account and privacy preferences.'),
          if (vm.actionError != null) ErrorBanner(vm.actionError!),
          SectionCard(
            title: 'Account',
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: LabeledField(
                        label: 'Email',
                        child: AppTextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          maxLength: AppLimits.emailMax,
                          validator: vm.validateEmail,
                          onSubmitted: _save,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: LabeledField(
                        label: 'Company name',
                        helper: 'Hidden from other users until you both connect.',
                        child: AppTextField(
                          controller: _company,
                          maxLength: AppLimits.companyMax,
                          validator: vm.validateCompany,
                          onSubmitted: _save,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: LabeledField(label: 'Public alias', child: AppTextField(initialValue: vm.alias, readOnly: true)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: LabeledField(label: 'Role', child: AppTextField(initialValue: vm.roleLabel, readOnly: true)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton(
              onPressed: vm.isBusy ? null : _save,
              child: vm.isBusy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save changes'),
            ),
          ),
        ],
      ),
    );
  }
}
