import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/error_mapper.dart';
import '../models/enums.dart';
import '../models/user_profile.dart';

/// Result of a sign-up: either signed in straight away, or email
/// confirmation is required first (depends on Supabase Auth settings).
enum SignUpOutcome { signedIn, confirmEmail }

abstract class AuthRepository {
  /// Emits `true` when a session exists, `false` when signed out.
  Stream<bool> get sessionChanges;
  bool get hasSession;
  String? get currentUserId;
  String? get currentEmail;

  Future<void> signIn({required String email, required String password});
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String companyName,
    required UserRole role,
  });
  Future<void> signOut();
  Future<void> sendPasswordReset(String email);
  Future<void> updateEmail(String email);
}

abstract class ProfileRepository {
  Future<UserProfile> fetchMyProfile();
  Future<UserProfile> updateCompanyName(String companyName);
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);
  final SupabaseClient _client;

  @override
  Stream<bool> get sessionChanges => _client.auth.onAuthStateChange.map((s) => s.session != null);

  @override
  bool get hasSession => _client.auth.currentSession != null;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  String? get currentEmail => _client.auth.currentUser?.email;

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String companyName,
    required UserRole role,
  }) async {
    // role + company_name are read by the `handle_new_user` trigger,
    // which creates the profile row and the anonymous alias.
    final res = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'role': role.dbValue, 'company_name': companyName},
    );
    return res.session != null ? SignUpOutcome.signedIn : SignUpOutcome.confirmEmail;
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> sendPasswordReset(String email) => _client.auth.resetPasswordForEmail(email);

  @override
  Future<void> updateEmail(String email) async {
    await _client.auth.updateUser(UserAttributes(email: email));
  }
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);
  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AppException('Your session has expired. Please log in again.');
    return id;
  }

  @override
  Future<UserProfile> fetchMyProfile() async {
    final row = await _client
        .from('profiles')
        .select('id, role, company_name, email, alias, alias_code')
        .eq('id', _uid)
        .single();
    return UserProfile.fromJson(row);
  }

  @override
  Future<UserProfile> updateCompanyName(String companyName) async {
    final row = await _client
        .from('profiles')
        .update({'company_name': companyName})
        .eq('id', _uid)
        .select('id, role, company_name, email, alias, alias_code')
        .single();
    return UserProfile.fromJson(row);
  }
}
