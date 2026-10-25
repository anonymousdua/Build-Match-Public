import 'package:buildmatch/core/utils/error_mapper.dart';
import 'package:buildmatch/models/enums.dart';
import 'package:buildmatch/services/auth_repository.dart';
import 'package:buildmatch/viewmodels/auth_view_models.dart';
import 'package:buildmatch/viewmodels/session_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../fakes.dart';

void main() {
  group('LoginViewModel', () {
    late FakeAuthRepository auth;
    late LoginViewModel vm;

    setUp(() {
      auth = FakeAuthRepository();
      vm = LoginViewModel(auth);
    });

    test('validators', () {
      expect(vm.validateEmail('nope'), isNotNull);
      expect(vm.validateEmail('you@company.ae'), isNull);
      expect(vm.validatePassword(''), isNotNull);
      expect(vm.validatePassword('anything'), isNull);
    });

    test('successful login cleans the email and passes the password unchanged', () async {
      final ok = await vm.login('  You@Company.AE ', ' pass word ');
      expect(ok, isTrue);
      expect(auth.lastEmail, 'you@company.ae');
      expect(auth.lastPassword, ' pass word ');
      expect(vm.actionError, isNull);
      expect(vm.isBusy, isFalse);
    });

    test('wrong credentials show a friendly message, never the raw exception', () async {
      auth.signInError = AuthException('Invalid login credentials');
      final ok = await vm.login('you@company.ae', 'bad');
      expect(ok, isFalse);
      expect(vm.actionError, 'Email or password is incorrect.');
    });

    test('unknown errors map to a generic message', () async {
      auth.signInError = StateError('socket blew up at 0x1234');
      await vm.login('you@company.ae', 'x');
      expect(vm.actionError, isNot(contains('0x1234')));
    });

    test('ignores a second submit while busy', () async {
      final f1 = vm.login('you@company.ae', 'x');
      final f2 = vm.login('you@company.ae', 'x');
      expect(await f2, isFalse);
      await f1;
      expect(auth.signInCalls, 1);
    });

    test('password reset validates the email first', () async {
      expect(await vm.sendPasswordReset('bad'), isFalse);
      expect(auth.resetCalls, 0);
      expect(vm.actionError, isNotNull);

      expect(await vm.sendPasswordReset('you@company.ae'), isTrue);
      expect(auth.resetCalls, 1);
      expect(vm.info, isNotNull);
    });

    test('toggleObscure flips visibility', () {
      expect(vm.obscurePassword, isTrue);
      vm.toggleObscure();
      expect(vm.obscurePassword, isFalse);
    });
  });

  group('SignUpViewModel', () {
    late FakeAuthRepository auth;
    late SignUpViewModel vm;

    setUp(() {
      auth = FakeAuthRepository();
      vm = SignUpViewModel(auth);
    });

    test('requires a role', () async {
      final ok = await vm.signUp(email: 'a@b.ae', password: 'Secur3pass', companyName: 'Gulf Build');
      expect(ok, isFalse);
      expect(vm.roleError, isNotNull);
      expect(auth.lastEmail, isNull);
    });

    test('selecting a role clears the role error', () async {
      await vm.signUp(email: 'a@b.ae', password: 'Secur3pass', companyName: 'Gulf Build');
      vm.selectRole(UserRole.supplier);
      expect(vm.roleError, isNull);
      expect(vm.role, UserRole.supplier);
    });

    test('sends cleaned values and the chosen role', () async {
      vm.selectRole(UserRole.contractor);
      final ok = await vm.signUp(email: ' New@Gulf.AE ', password: 'Secur3pass', companyName: '  Gulf   Build  LLC ');
      expect(ok, isTrue);
      expect(auth.lastEmail, 'new@gulf.ae');
      expect(auth.lastCompany, 'Gulf Build LLC');
      expect(auth.lastRole, UserRole.contractor);
      expect(vm.outcome, SignUpOutcome.signedIn);
    });

    test('reports when email confirmation is required', () async {
      auth.signUpOutcome = SignUpOutcome.confirmEmail;
      vm.selectRole(UserRole.supplier);
      await vm.signUp(email: 'a@b.ae', password: 'Secur3pass', companyName: 'Desert Blocks');
      expect(vm.outcome, SignUpOutcome.confirmEmail);
    });

    test('duplicate account error is friendly', () async {
      auth.signUpError = AuthException('User already registered');
      vm.selectRole(UserRole.supplier);
      await vm.signUp(email: 'a@b.ae', password: 'Secur3pass', companyName: 'Desert Blocks');
      expect(vm.actionError, 'An account with this email already exists.');
    });

    test('validators', () {
      expect(vm.validateCompany('A'), contains('at least 2'));
      expect(vm.validateCompany('<script>x</script>'), contains('not allowed'));
      expect(vm.validateCompany('Gulf Build Contracting LLC'), isNull);
      expect(vm.validatePassword('weak'), isNotNull);
      expect(vm.validateConfirm('Secur3pass', 'Secur3pass'), isNull);
      expect(vm.validateConfirm('x', 'Secur3pass'), isNotNull);
    });
  });

  group('SessionViewModel', () {
    test('signed-out start, then loads the profile after login', () async {
      final auth = FakeAuthRepository();
      final profiles = FakeProfileRepository();
      final session = SessionViewModel(auth, profiles);
      await flushEvents();
      expect(session.status, SessionStatus.signedOut);

      await auth.signIn(email: 'you@company.ae', password: 'x');
      await flushEvents();
      expect(session.status, SessionStatus.ready);
      expect(session.profile?.alias, 'Contractor #C-4821');
      expect(session.homeRoute, '/contractor');

      await session.signOut();
      await flushEvents();
      expect(session.status, SessionStatus.signedOut);
      expect(session.profile, isNull);
      session.dispose();
    });
  });

  test('AppException messages pass straight through the mapper', () {
    expect(ErrorMapper.message(const AppException('Custom message')), 'Custom message');
  });
}
