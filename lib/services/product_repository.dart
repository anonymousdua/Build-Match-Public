import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/error_mapper.dart';
import '../models/product.dart';

/// The SUPPLIER's own catalogue. RLS limits every query to the signed-in
/// supplier's rows; supplier_id is filled by the database default.
abstract class ProductRepository {
  Future<List<Product>> fetchMine();
  Future<Product> fetch(String id);
  Future<Product> create(ProductInput input);
  Future<Product> update(String id, ProductInput input);
  Future<void> delete(String id);

  /// Uploads to `product-images/<uid>/<random>.<ext>`; returns the path.
  Future<String> uploadImage({required String fileName, required Uint8List bytes});
  Future<String> imageUrl(String path);
}

class SupabaseProductRepository implements ProductRepository {
  SupabaseProductRepository(this._client);
  final SupabaseClient _client;

  static const _columns =
      'id, name, category_id, description, specifications, unit, available_quantity, '
      'price_min, price_max, lead_time_days, is_active, image_path';

  @override
  Future<List<Product>> fetchMine() async {
    final rows = await _client.from('products').select(_columns).order('name');
    return rows.map(Product.fromJson).toList();
  }

  @override
  Future<Product> fetch(String id) async {
    final row = await _client.from('products').select(_columns).eq('id', id).single();
    return Product.fromJson(row);
  }

  @override
  Future<Product> create(ProductInput input) async {
    final row = await _client.from('products').insert(input.toJson()).select(_columns).single();
    return Product.fromJson(row);
  }

  @override
  Future<Product> update(String id, ProductInput input) async {
    final row = await _client.from('products').update(input.toJson()).eq('id', id).select(_columns).single();
    return Product.fromJson(row);
  }

  @override
  Future<void> delete(String id) async {
    await _client.from('products').delete().eq('id', id);
  }

  @override
  Future<String> uploadImage({required String fileName, required Uint8List bytes}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AppException('Your session has expired. Please log in again.');
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    if (!AppConstants.imageExtensions.contains(ext)) {
      throw const AppException('Only PNG or JPG images can be uploaded.');
    }
    if (bytes.length > AppLimits.imageMaxBytes) throw const AppException('Images must be 5 MB or smaller.');

    final rng = Random.secure();
    final token = List.generate(16, (_) => rng.nextInt(16).toRadixString(16)).join();
    final path = '$uid/$token.${ext == 'jpeg' ? 'jpg' : ext}';
    await _client.storage.from(AppConstants.productImagesBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: AppConstants.mimeForExtension(ext)),
        );
    return path;
  }

  @override
  Future<String> imageUrl(String path) =>
      _client.storage.from(AppConstants.productImagesBucket).createSignedUrl(path, 3600);
}
