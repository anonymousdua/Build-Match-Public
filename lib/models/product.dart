import '../core/utils/formatters.dart';
import 'enums.dart';

/// Supplier's own catalogue product (`products`).
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.unit,
    required this.isActive,
    this.description,
    this.specifications,
    this.availableQuantity,
    this.priceMin,
    this.priceMax,
    this.leadTimeDays,
    this.imagePath,
  });

  final String id;
  final String name;
  final String categoryId;
  final String? description;
  final String? specifications;
  final UnitType unit;
  final double? availableQuantity;
  final double? priceMin;
  final double? priceMax;
  final int? leadTimeDays;
  final bool isActive;
  final String? imagePath;

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        name: json['name'] as String,
        categoryId: json['category_id'] as String,
        description: json['description'] as String?,
        specifications: json['specifications'] as String?,
        unit: UnitType.fromDb(json['unit'] as String?),
        availableQuantity: Fmt.parseDouble(json['available_quantity']),
        priceMin: Fmt.parseDouble(json['price_min']),
        priceMax: Fmt.parseDouble(json['price_max']),
        leadTimeDays: json['lead_time_days'] == null ? null : Fmt.parseInt(json['lead_time_days']),
        isActive: json['is_active'] as bool? ?? true,
        imagePath: json['image_path'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        ...ProductInput(
          name: name,
          categoryId: categoryId,
          description: description,
          specifications: specifications,
          unit: unit,
          availableQuantity: availableQuantity,
          priceMin: priceMin,
          priceMax: priceMax,
          leadTimeDays: leadTimeDays,
          isActive: isActive,
          imagePath: imagePath,
        ).toJson(),
      };
}

/// Values written to `products` (only the columns the app may write).
class ProductInput {
  const ProductInput({
    required this.name,
    required this.categoryId,
    required this.unit,
    this.description,
    this.specifications,
    this.availableQuantity,
    this.priceMin,
    this.priceMax,
    this.leadTimeDays,
    this.isActive = true,
    this.imagePath,
  });

  final String name;
  final String categoryId;
  final String? description;
  final String? specifications;
  final UnitType unit;
  final double? availableQuantity;
  final double? priceMin;
  final double? priceMax;
  final int? leadTimeDays;
  final bool isActive;
  final String? imagePath;

  Map<String, dynamic> toJson() => {
        'name': name,
        'category_id': categoryId,
        'description': description,
        'specifications': specifications,
        'unit': unit.dbValue,
        'available_quantity': availableQuantity,
        'price_min': priceMin,
        'price_max': priceMax,
        'lead_time_days': leadTimeDays,
        'is_active': isActive,
        'image_path': imagePath,
      };
}
