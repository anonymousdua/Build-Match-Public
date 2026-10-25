import '../core/constants/app_constants.dart';
import '../core/utils/input_sanitizer.dart';
import '../models/enums.dart';
import '../services/auth_repository.dart';
import 'base_view_model.dart';

class LoginViewModel extends BaseViewModel {
  LoginViewModel(this._auth);
  final AuthRepository _auth;

  bool _obscure = true;
  bool get obscurePassword => _obscure;
  String? _info;
  String? get info => _info;

  void toggleObscure() {
    _obscure = !_obscure;
    notifyListeners();
  }

  String? validateEmail(String? v) => InputSanitizer.validateEmail(v);
  String? validatePassword(String? v) => InputSanitizer.validateLoginPassword(v);

  /// On success the SessionViewModel picks up the new session and the
  /// router redirects to the right dashboard.
  Future<bool> login(String email, String password) {
    _info = null;
    return runAction(() => _auth.signIn(email: InputSanitizer.cleanEmail(email), password: password));
  }

  Future<bool> sendPasswordReset(String email) async {
    final err = validateEmail(email);
    if (err != null) {
      setActionError(err);
      return false;
    }
    final ok = await runAction(() => _auth.sendPasswordReset(InputSanitizer.cleanEmail(email)));
    if (ok) {
      _info = 'If an account exists for that email, a reset link is on its way.';
      notifyListeners();
    }
    return ok;
  }
}

class SignUpViewModel extends BaseViewModel {
  SignUpViewModel(this._auth);
  final AuthRepository _auth;

  UserRole? _role;
  UserRole? get role => _role;
  String? _roleError;
  String? get roleError => _roleError;
  SignUpOutcome? _outcome;
  SignUpOutcome? get outcome => _outcome;

  void selectRole(UserRole role) {
    _role = role;
    _roleError = null;
    notifyListeners();
  }

  String? validateEmail(String? v) => InputSanitizer.validateEmail(v);
  String? validatePassword(String? v) =>
      InputSanitizer.validatePassword(v, min: AppLimits.passwordMin, max: AppLimits.passwordMax);
  String? validateConfirm(String? v, String password) => InputSanitizer.validateConfirmPassword(v, password);
  String? validateCompany(String? v) => InputSanitizer.validateText(
        v,
        field: 'Company name',
        min: AppLimits.companyMin,
        max: AppLimits.companyMax,
      );

  /// Call after the Form validated. Returns true on success.
  Future<bool> signUp({
    required String email,
    required String password,
    required String companyName,
  }) async {
    if (_role == null) {
      _roleError = 'Choose whether you are a contractor or a supplier.';
      notifyListeners();
      return false;
    }
    return runAction(() async {
      _outcome = await _auth.signUp(
        email: InputSanitizer.cleanEmail(email),
        password: password,
        companyName: InputSanitizer.clean(companyName),
        role: _role!,
      );
    });
  }
}
