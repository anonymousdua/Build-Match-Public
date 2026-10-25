import '../core/constants/app_constants.dart';
import '../core/utils/input_sanitizer.dart';
import '../services/auth_repository.dart';
import 'base_view_model.dart';
import 'session_view_model.dart';

/// Settings → Account (email, company name). Alias and role are read-only.
class SettingsViewModel extends BaseViewModel {
  SettingsViewModel(this._session, this._auth, this._profiles);

  final SessionViewModel _session;
  final AuthRepository _auth;
  final ProfileRepository _profiles;

  String get email => _session.email ?? '';
  String get companyName => _session.profile?.companyName ?? '';
  String get alias => _session.profile?.alias ?? '';
  String get roleLabel => _session.profile?.role.label ?? '';

  String? _info;
  String? get info => _info;

  String? validateEmail(String? v) => InputSanitizer.validateEmail(v);
  String? validateCompany(String? v) =>
      InputSanitizer.validateText(v, field: 'Company name', min: AppLimits.companyMin, max: AppLimits.companyMax);

  Future<bool> save({required String email, required String companyName}) async {
    _info = null;
    final cleanEmail = InputSanitizer.cleanEmail(email);
    final cleanCompany = InputSanitizer.clean(companyName);
    final emailChanged = cleanEmail != this.email.toLowerCase();
    final companyChanged = cleanCompany != this.companyName;

    if (!emailChanged && !companyChanged) {
      _info = 'Nothing to save.';
      notifyListeners();
      return true;
    }

    final ok = await runAction(() async {
      if (companyChanged) {
        _session.updateProfile(await _profiles.updateCompanyName(cleanCompany));
      }
      if (emailChanged) await _auth.updateEmail(cleanEmail);
    });
    if (ok) {
      _info = emailChanged
          ? 'Saved. Check both inboxes to confirm the new email address.'
          : 'Changes saved.';
      notifyListeners();
    }
    return ok;
  }
}
