/// Cleans and validates user input before it reaches a repository.
///
/// SQL injection is prevented structurally: the app only uses the Supabase
/// query builder and parameterised RPC calls (values are never concatenated
/// into SQL), and the database re-checks lengths/characters with CHECK
/// constraints. This class is the first, user-friendly line of defence.
class InputSanitizer {
  InputSanitizer._();

  // Control characters except \t \n \r (allowed in multiline text).
  static final RegExp _controlMultiline = RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]');
  // All control characters (single-line text).
  static final RegExp _controlSingle = RegExp(r'[\u0000-\u001F\u007F]');
  static final RegExp _spaces = RegExp(r'[ \t]+');
  static final RegExp _manyNewlines = RegExp(r'\n{3,}');

  static final RegExp _email = RegExp(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$",
  );

  /// Patterns that have no business in this app's free text. Rejected (not
  /// silently stripped) so the user knows why their input was refused.
  static final List<RegExp> _suspicious = [
    RegExp(r'<\s*/?\s*script', caseSensitive: false),
    RegExp(r'javascript\s*:', caseSensitive: false),
    RegExp(r'on\w+\s*=\s*["\x27]', caseSensitive: false), // onerror="..."
    RegExp(r';\s*--'), // statement terminator + SQL comment
    RegExp(r'/\*|\*/'), // SQL block comments
    RegExp(r"\x27\s*or\s+\x27?\d+\x27?\s*=\s*\x27?\d+", caseSensitive: false), // ' or 1=1
    RegExp(r'\b(drop|truncate|alter)\s+table\b', caseSensitive: false),
    RegExp(r'\bunion\s+(all\s+)?select\b', caseSensitive: false),
  ];

  // ---------------------------------------------------------------------------
  // Cleaning
  // ---------------------------------------------------------------------------

  /// Single-line text: strips control chars, collapses spaces, trims.
  static String clean(String? value) {
    if (value == null) return '';
    return value.replaceAll(_controlSingle, ' ').replaceAll(_spaces, ' ').trim();
  }

  /// Multiline text: normalises newlines, strips other control chars,
  /// collapses runs of blank lines and trims each line's trailing spaces.
  static String cleanMultiline(String? value) {
    if (value == null) return '';
    final normalised = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll(_controlMultiline, '');
    final lines = normalised.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t]+$'), ''));
    return lines.join('\n').replaceAll(_manyNewlines, '\n\n').trim();
  }

  /// Cleans and returns null for empty strings (for optional columns).
  static String? cleanOrNull(String? value, {bool multiline = false}) {
    final v = multiline ? cleanMultiline(value) : clean(value);
    return v.isEmpty ? null : v;
  }

  static String cleanEmail(String? value) => clean(value).toLowerCase();

  static bool isSuspicious(String value) => _suspicious.any((r) => r.hasMatch(value));

  // ---------------------------------------------------------------------------
  // Validators (return an error message, or null when valid). They clean the
  // value first so validation matches what will actually be saved.
  // ---------------------------------------------------------------------------

  static String? validateText(
    String? value, {
    required String field,
    bool required = true,
    int min = 1,
    required int max,
    bool multiline = false,
  }) {
    final v = multiline ? cleanMultiline(value) : clean(value);
    if (v.isEmpty) return required ? '$field is required.' : null;
    if (v.length < min) return '$field must be at least $min characters.';
    if (v.length > max) return '$field must be at most $max characters.';
    if (isSuspicious(v)) return '$field contains characters or patterns that are not allowed.';
    return null;
  }

  static String? validateEmail(String? value) {
    final v = cleanEmail(value);
    if (v.isEmpty) return 'Email is required.';
    if (v.length > 254) return 'Email is too long.';
    if (!_email.hasMatch(v)) return 'Enter a valid email address.';
    return null;
  }

  static String? validatePassword(String? value, {int min = 8, int max = 72}) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required.';
    if (v.length < min) return 'Password must be at least $min characters.';
    if (v.length > max) return 'Password must be at most $max characters.';
    if (_controlSingle.hasMatch(v)) return 'Password contains invalid characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return 'Use at least one letter and one number.';
    }
    return null;
  }

  /// Login only checks presence – the server decides if it is correct.
  static String? validateLoginPassword(String? value) =>
      (value == null || value.isEmpty) ? 'Password is required.' : null;

  static String? validateConfirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) return 'Confirm your password.';
    if (value != password) return 'Passwords do not match.';
    return null;
  }

  /// Parses a user-typed number ("1,250.50", " 18 ") or returns null.
  static double? parseNumber(String? value) {
    final v = clean(value).replaceAll(',', '');
    if (v.isEmpty) return null;
    if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(v)) return null;
    return double.tryParse(v);
  }

  static int? parseInt(String? value) {
    final v = clean(value).replaceAll(',', '');
    if (!RegExp(r'^-?\d+$').hasMatch(v)) return null;
    return int.tryParse(v);
  }

  static String? validateNumber(
    String? value, {
    required String field,
    bool required = true,
    bool positive = true,
    bool allowZero = false,
    double max = 1000000000,
    int maxDecimals = 3,
  }) {
    final raw = clean(value);
    if (raw.isEmpty) return required ? '$field is required.' : null;
    final n = parseNumber(raw);
    if (n == null) return '$field must be a number.';
    if (positive && (allowZero ? n < 0 : n <= 0)) {
      return allowZero ? '$field cannot be negative.' : '$field must be greater than 0.';
    }
    if (n > max) return '$field is too large.';
    final dot = raw.replaceAll(',', '').indexOf('.');
    if (dot >= 0 && raw.replaceAll(',', '').length - dot - 1 > maxDecimals) {
      return '$field can have at most $maxDecimals decimals.';
    }
    return null;
  }

  static String? validateInt(String? value, {required String field, bool required = true, int min = 0, required int max}) {
    final raw = clean(value);
    if (raw.isEmpty) return required ? '$field is required.' : null;
    final n = parseInt(raw);
    if (n == null) return '$field must be a whole number.';
    if (n < min || n > max) return '$field must be between $min and $max.';
    return null;
  }

  /// Date must be present (when required) and not before [notBefore] (default today).
  static String? validateDate(DateTime? value, {required String field, bool required = true, DateTime? notBefore}) {
    if (value == null) return required ? '$field is required.' : null;
    final min = _dateOnly(notBefore ?? DateTime.now());
    if (_dateOnly(value).isBefore(min)) return '$field cannot be in the past.';
    if (value.year > 2100) return '$field is too far in the future.';
    return null;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
