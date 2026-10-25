import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../services/auth_repository.dart';
import '../../viewmodels/auth_view_models.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';
import 'auth_layout.dart';

class SignUpView extends StatefulWidget {
  const SignUpView({super.key});

  @override
  State<SignUpView> createState() => _SignUpViewState();
}

class _SignUpViewState extends State<SignUpView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _company = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _company.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final vm = context.read<SignUpViewModel>();
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    await vm.signUp(
      email: _email.text,
      password: _password.text,
      companyName: _company.text,
    );
    // signed in -> router redirects; confirm email -> card shows a notice
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SignUpViewModel>();

    if (vm.outcome == SignUpOutcome.confirmEmail) {
      return AuthLayout(
        card: EmptyView(
          icon: Icons.mark_email_read_outlined,
          title: 'Confirm your email',
          message:
              'We sent a confirmation link to ${_email.text.trim()}. Open it, then log in.',
          action: ElevatedButton(
            onPressed: () => context.go(Routes.login),
            child: const Text('Go to login'),
          ),
        ),
      );
    }

    return AuthLayout(
      card: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Create your account',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your role decides which dashboard you see.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 22),
              if (vm.actionError != null) ErrorBanner(vm.actionError!),
              Row(
                children: [
                  Expanded(
                    child: _RoleCard(
                      selected: vm.role == UserRole.contractor,
                      icon: const HardHatIcon(),
                      title: "I'm a Contractor",
                      subtitle: 'Post RFQs and compare supplier BOQs.',
                      onTap: () => vm.selectRole(UserRole.contractor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _RoleCard(
                      selected: vm.role == UserRole.supplier,
                      icon: const Icon(
                        Icons.local_shipping_outlined,
                        size: 22,
                        color: AppColors.primary,
                      ),
                      title: "I'm a Supplier",
                      subtitle: 'List products and answer matched RFQs.',
                      onTap: () => vm.selectRole(UserRole.supplier),
                    ),
                  ),
                ],
              ),
              if (vm.roleError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    vm.roleError!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              LabeledField(
                label: 'Email',
                child: AppTextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  maxLength: AppLimits.emailMax,
                  validator: vm.validateEmail,
                  onSubmitted: _submit,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: LabeledField(
                      label: 'Password',
                      child: AppTextField(
                        controller: _password,
                        obscure: true,
                        autofillHints: const [AutofillHints.newPassword],
                        maxLength: AppLimits.passwordMax,
                        validator: vm.validatePassword,
                        onSubmitted: _submit,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledField(
                      label: 'Confirm password',
                      child: AppTextField(
                        controller: _confirm,
                        obscure: true,
                        maxLength: AppLimits.passwordMax,
                        validator: (v) => vm.validateConfirm(v, _password.text),
                        onSubmitted: _submit,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: 'Company name',
                helper:
                    'Your company name stays hidden from other users until you both agree to connect.',
                helperIcon: Icons.lock_outline,
                child: AppTextField(
                  controller: _company,
                  autofillHints: const [AutofillHints.organizationName],
                  maxLength: AppLimits.companyMax,
                  validator: vm.validateCompany,
                  onSubmitted: _submit,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: vm.isBusy ? null : _submit,
                  child:
                      vm.isBusy
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Text('Create account'),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Already have an account? ',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  InkWell(
                    onTap: () => context.go(Routes.login),
                    child: const Text(
                      'Login',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final Widget icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFF1F6FD) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 120),
          //height: 120,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.borderStrong,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
