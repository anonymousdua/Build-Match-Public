import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Reads public Supabase settings from the bundled `.env` asset.
///
/// Only the anon (public) key is used. A desktop build can be unpacked and
/// its assets read, so the key is NOT a secret: all data protection is done
/// by Row Level Security and SECURITY DEFINER RPCs on the database.
class EnvConfig {
  EnvConfig._();

  static late final String supabaseUrl;
  static late final String supabaseAnonKey;

  static Future<void> load() async {
    await dotenv.load(fileName: '.env');
    supabaseUrl = _require('SUPABASE_URL');
    supabaseAnonKey = _require('SUPABASE_ANON_KEY');

    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const EnvConfigException('SUPABASE_URL must be a valid https URL.');
    }
  }

  static String _require(String key) {
    final value = dotenv.env[key]?.trim() ?? '';
    if (value.isEmpty || value.startsWith('your-')) {
      throw EnvConfigException('$key is missing in .env (see .env.example).');
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
