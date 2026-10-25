import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/utils/error_mapper.dart';
import '../models/enums.dart';
import '../models/user_profile.dart';
import '../services/auth_repository.dart';

enum SessionStatus { initializing, signedOut, loadingProfile, ready, profileError }

/// App-wide auth state. The router listens to it for role-based redirects.
class SessionViewModel extends ChangeNotifier {
  SessionViewModel(this._auth, this._profiles) {
    _sub = _auth.sessionChanges.listen(_onSession);
    unawaited(_onSession(_auth.hasSession));
  }

  final AuthRepository _auth;
  final ProfileRepository _profiles;
  StreamSubscription<bool>? _sub;
  int _generation = 0; // ignores results of outdated profile loads

  SessionStatus _status = SessionStatus.initializing;
  UserProfile? _profile;
  String? _error;

  SessionStatus get status => _status;
  UserProfile? get profile => _profile;
  String? get error => _error;
  UserRole? get role => _profile?.role;
  bool get isReady => _status == SessionStatus.ready && _profile != null;
  String? get email => _auth.currentEmail ?? _profile?.email;

  /// Landing route for the signed-in role.
  String get homeRoute => _profile?.role == UserRole.supplier ? '/supplier' : '/contractor';

  Future<void> _onSession(bool hasSession) async {
    final gen = ++_generation;
    if (!hasSession) {
      _profile = null;
      _error = null;
      _status = SessionStatus.signedOut;
      notifyListeners();
      return;
    }
    // Token refreshes etc. for the same user don't need a reload.
    if (_status == SessionStatus.ready && _profile?.id == _auth.currentUserId) return;

    _status = SessionStatus.loadingProfile;
    notifyListeners();
    try {
      final p = await _profiles.fetchMyProfile();
      if (gen != _generation) return;
      _profile = p;
      _status = SessionStatus.ready;
    } catch (e) {
      if (gen != _generation) return;
      _error = ErrorMapper.message(e);
      _status = SessionStatus.profileError;
    }
    notifyListeners();
  }

  Future<void> retry() => _onSession(_auth.hasSession);

  void updateProfile(UserProfile profile) {
    _profile = profile;
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } finally {
      // make sure the UI leaves protected pages even if the network call failed
      await _onSession(false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
