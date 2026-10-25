import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../viewmodels/auth_view_models.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';
import 'auth_layout.dart';

/// Login (email + password). Demo buttons from the design are removed.
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final vm = context.read<LoginViewModel>();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await vm.login(_email.text, _password.text);
    // success: the router redirects automatically once the session is ready
  }

  Future<void> _forgotPassword() async {
    final vm = context.read<LoginViewModel>();
    await vm.sendPasswordReset(_email.text);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LoginViewModel>();
    return AuthLayout(
      card: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Welcome back', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.4)),
              const SizedBox(height: 6),
              const Text('Log in to your account to continue.', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 26),
              if (vm.actionError != null) ErrorBanner(vm.actionError!),
              if (vm.info != null) InfoBanner(vm.info!, icon: Icons.mark_email_read_outlined),
              LabeledField(
                label: 'Email',
                child: AppTextField(
                  controller: _email,
                  hint: 'you@company.ae',
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  maxLength: AppLimits.emailMax,
                  validator: vm.validateEmail,
                  onSubmitted: _submit,
                ),
              ),
              const SizedBox(height: 18),
              LabeledField(
                label: 'Password',
                child: AppTextField(
                  controller: _password,
                  hint: '••••••••',
                  obscure: vm.obscurePassword,
                  autofillHints: const [AutofillHints.password],
                  maxLength: AppLimits.passwordMax,
                  validator: vm.validatePassword,
                  onSubmitted: _submit,
                  suffix: IconButton(
                    tooltip: vm.obscurePassword ? 'Show password' : 'Hide password',
                    icon: Icon(vm.obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                    onPressed: vm.toggleObscure,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: vm.isBusy ? null : _forgotPassword,
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: vm.isBusy ? null : _submit,
                  child: vm.isBusy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Login'),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? ", style: TextStyle(color: AppColors.textSecondary)),
                  InkWell(
                    onTap: () => context.go(Routes.signup),
                    child: const Text('Sign up', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
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
