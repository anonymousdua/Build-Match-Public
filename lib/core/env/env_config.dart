import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Public Supabase settings.
///
/// Two sources, first match wins:
///  1. Build-time defines – used for hosted web builds (e.g. Vercel):
///     flutter build web --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
///     or --dart-define-from-file=.env
///  2. The bundled `.env` asset – used for local `flutter run`.
///
/// Only the anon (public) key is used. Anything shipped to a browser or a
/// desktop install can be read by the user, so the key is NOT a secret: data
/// is protected by Row Level Security and SECURITY DEFINER RPCs.
class EnvConfig {
  EnvConfig._();

  static const _definedUrl = String.fromEnvironment('SUPABASE_URL');
  static const _definedKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static late final String supabaseUrl;
  static late final String supabaseAnonKey;

  static Future<void> load() async {
    if (_definedUrl.isNotEmpty && _definedKey.isNotEmpty) {
      supabaseUrl = _definedUrl.trim();
      supabaseAnonKey = _definedKey.trim();
    } else {
      await dotenv.load(fileName: '.env');
      supabaseUrl = _require('SUPABASE_URL');
      supabaseAnonKey = _require('SUPABASE_ANON_KEY');
    }

    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const EnvConfigException('SUPABASE_URL must be a valid https URL.');
    }
  }

  static String _require(String key) {
    final value = dotenv.env[key]?.trim() ?? '';
    if (value.isEmpty || value.startsWith('your-')) {
      throw EnvConfigException('$key is missing (set it in .env or pass --dart-define=$key=...).');
    }
    return value;
  }
}

class EnvConfigException implements Exception {
  const EnvConfigException(this.message);
  final String message;

  @override
  String toString() => message;
}
