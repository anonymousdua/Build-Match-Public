import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/category.dart';

abstract class CategoryRepository {
  Future<List<Category>> fetchAll();
  String nameFor(String id);
}

/// Categories are reference data, so they are cached after the first load.
class SupabaseCategoryRepository implements CategoryRepository {
  SupabaseCategoryRepository(this._client);
  final SupabaseClient _client;

  List<Category>? _cache;

  @override
  Future<List<Category>> fetchAll() async {
    if (_cache != null) return _cache!;
    final rows = await _client.from('categories').select('id, name').order('sort_order');
    _cache = rows.map(Category.fromJson).toList();
    return _cache!;
  }

  @override
  String nameFor(String id) {
    for (final c in _cache ?? const <Category>[]) {
      if (c.id == id) return c.name;
    }
    return id;
  }
}
