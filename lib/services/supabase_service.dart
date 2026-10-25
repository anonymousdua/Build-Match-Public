import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env/env_config.dart';

/// Owns the single Supabase client. Repositories receive the client through
/// their constructors so they can be swapped for fakes in tests.
class SupabaseService {
  SupabaseService._();

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      anonKey: EnvConfig.supabaseAnonKey, // public key only – see README
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: true),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}

/// Helpers for RPC results (`rpc()` returns `dynamic`).
/// A `returns table` RPC comes back as a list of row maps.
List<Map<String, dynamic>> rpcRows(dynamic result) =>
    ((result as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

/// First row of a `returns table` RPC, or an empty map.
Map<String, dynamic> rpcFirstRow(dynamic result) {
  final rows = rpcRows(result);
  return rows.isEmpty ? <String, dynamic>{} : rows.first;
}
