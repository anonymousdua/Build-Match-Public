import 'dart:typed_data';

import '../../core/constants/app_constants.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/input_sanitizer.dart';
import '../../models/category.dart';
import '../../models/enums.dart';
import '../../models/product.dart';
import '../../services/category_repository.dart';
import '../../services/product_repository.dart';
import '../base_view_model.dart';

/// Add product / edit product screen.
class ProductFormViewModel extends BaseViewModel {
  ProductFormViewModel(this._products, this._categories, {this.productId});

  final ProductRepository _products;
  final CategoryRepository _categories;
  final String? productId;

  bool get isEdit => productId != null;

  List<Category> _categoryList = const [];
  List<Category> get categories => _categoryList;

  // Form state (text fields use initialValue + onChanged)
  String name = '';
  String? categoryId;
  String description = '';
  String specifications = '';
  UnitType unit = UnitType.bag;
  String availableText = '';
  String priceMinText = '';
  String priceMaxText = '';
  String leadTimeText = '';
  bool isActive = true;
  String? categoryError;

  // Image
  String? _imagePath; // stored path
  String? _imageUrl; // signed URL for an existing image
  Uint8List? _newImageBytes;
  String? _newImageName;
  String? imageError;

  String? get imageUrl => _imageUrl;
  Uint8List? get newImageBytes => _newImageBytes;
  bool get hasImage => _newImageBytes != null || _imageUrl != null;

  bool saved = false;

  Future<void> load() async {
    await runLoad(() async {
      _categoryList = await _categories.fetchAll();
      if (productId == null) return;
      final p = await _products.fetch(productId!);
      name = p.name;
      categoryId = p.categoryId;
      description = p.description ?? '';
      specifications = p.specifications ?? '';
      unit = p.unit;
      availableText = Fmt.plainNumber(p.availableQuantity);
      priceMinText = Fmt.plainNumber(p.priceMin);
      priceMaxText = Fmt.plainNumber(p.priceMax);
      leadTimeText = p.leadTimeDays?.toString() ?? '';
      isActive = p.isActive;
      _imagePath = p.imagePath;
      if (_imagePath != null) {
        try {
          _imageUrl = await _products.imageUrl(_imagePath!);
        } catch (_) {
          _imageUrl = null; // image is optional; don't fail the page
        }
      }
    });
  }

  void setCategory(String? id) {
    categoryId = id;
    categoryError = null;
    notifyListeners();
  }

  void setUnit(UnitType u) {
    unit = u;
    notifyListeners();
  }

  void setActive(bool v) {
    isActive = v;
    notifyListeners();
  }

  void setImage(String fileName, Uint8List bytes) {
    imageError = null;
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    if (!AppConstants.imageExtensions.contains(ext)) {
      imageError = 'Choose a PNG or JPG image.';
    } else if (bytes.length > AppLimits.imageMaxBytes) {
      imageError = 'Images must be 5 MB or smaller.';
    } else {
      _newImageBytes = bytes;
      _newImageName = fileName;
    }
    notifyListeners();
  }

  void removeImage() {
    _newImageBytes = null;
    _newImageName = null;
    _imageUrl = null;
    _imagePath = null;
    notifyListeners();
  }

  // ---- validators ----------------------------------------------------------
  String? validateName(String? v) => InputSanitizer.validateText(v,
      field: 'Product name', min: AppLimits.productNameMin, max: AppLimits.productNameMax);
  String? validateDescription(String? v) => InputSanitizer.validateText(v,
      field: 'Description', required: false, max: AppLimits.productDescriptionMax, multiline: true);
  String? validateSpecs(String? v) => InputSanitizer.validateText(v,
      field: 'Specifications', required: false, max: AppLimits.productSpecsMax, multiline: true);
  String? validateAvailable(String? v) => InputSanitizer.validateNumber(v,
      field: 'Available quantity', required: false, allowZero: true, max: AppLimits.quantityMax);
  String? validatePriceMin(String? v) => InputSanitizer.validateNumber(v,
      field: 'Price', required: false, max: AppLimits.priceMax, maxDecimals: 2);
  String? validateLeadTime(String? v) =>
      InputSanitizer.validateInt(v, field: 'Lead time', required: false, max: AppLimits.leadTimeMax);

  String? validatePriceMax(String? v) {
    final basic = InputSanitizer.validateNumber(v, field: 'Max price', required: false, max: AppLimits.priceMax, maxDecimals: 2);
    if (basic != null) return basic;
    final min = InputSanitizer.parseNumber(priceMinText);
    final max = InputSanitizer.parseNumber(v);
    if (min != null && max != null && max < min) return 'Max price must be at least the base price.';
    return null;
  }

  Future<bool> save({required bool formValid}) async {
    categoryError = categoryId == null ? 'Choose a category.' : null;
    notifyListeners();
    if (!formValid || categoryError != null) return false;

    return runAction(() async {
      var imagePath = _imagePath;
      if (_newImageBytes != null) {
        imagePath = await _products.uploadImage(fileName: _newImageName!, bytes: _newImageBytes!);
      }
      final input = ProductInput(
        name: InputSanitizer.clean(name),
        categoryId: categoryId!,
        description: InputSanitizer.cleanOrNull(description, multiline: true),
        specifications: InputSanitizer.cleanOrNull(specifications, multiline: true),
        unit: unit,
        availableQuantity: InputSanitizer.parseNumber(availableText),
        priceMin: InputSanitizer.parseNumber(priceMinText),
        priceMax: InputSanitizer.parseNumber(priceMaxText) ?? InputSanitizer.parseNumber(priceMinText),
        leadTimeDays: InputSanitizer.parseInt(leadTimeText),
        isActive: isActive,
        imagePath: imagePath,
      );
      if (productId == null) {
        await _products.create(input);
      } else {
        await _products.update(productId!, input);
      }
      saved = true;
    });
  }
}
