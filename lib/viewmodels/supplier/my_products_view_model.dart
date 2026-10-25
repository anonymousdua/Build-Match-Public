import '../../core/utils/input_sanitizer.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../services/category_repository.dart';
import '../../services/product_repository.dart';
import '../base_view_model.dart';

enum ProductSortField { name, category, available, price, leadTime }

class MyProductsViewModel extends BaseViewModel {
  MyProductsViewModel(this._products, this._categories, {String? initialQuery})
      : _query = InputSanitizer.clean(initialQuery);

  final ProductRepository _products;
  final CategoryRepository _categories;

  List<Product> _all = const [];
  List<Category> _categoryList = const [];
  String _query;
  String? _categoryFilter;
  ProductSortField _sortField = ProductSortField.name;
  bool _ascending = true;

  List<Category> get categories => _categoryList;
  String get query => _query;
  String? get categoryFilter => _categoryFilter;
  ProductSortField get sortField => _sortField;
  bool get ascending => _ascending;
  bool get hasAny => _all.isNotEmpty;

  String categoryName(String id) => _categories.nameFor(id);

  List<Product> get visible {
    final q = _query.toLowerCase();
    final list = _all.where((p) {
      if (_categoryFilter != null && p.categoryId != _categoryFilter) return false;
      return q.isEmpty || p.name.toLowerCase().contains(q) || (p.specifications ?? '').toLowerCase().contains(q);
    }).toList();

    int cmpNum(num? a, num? b) => (a ?? -1).compareTo(b ?? -1);
    int cmp(Product a, Product b) {
      switch (_sortField) {
        case ProductSortField.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case ProductSortField.category:
          return categoryName(a.categoryId).compareTo(categoryName(b.categoryId));
        case ProductSortField.available:
          return cmpNum(a.availableQuantity, b.availableQuantity);
        case ProductSortField.price:
          return cmpNum(a.priceMin ?? a.priceMax, b.priceMin ?? b.priceMax);
        case ProductSortField.leadTime:
          return cmpNum(a.leadTimeDays, b.leadTimeDays);
      }
    }

    list.sort((a, b) => _ascending ? cmp(a, b) : cmp(b, a));
    return list;
  }

  Future<void> load() async {
    await runLoad(() async {
      _categoryList = await _categories.fetchAll();
      _all = await _products.fetchMine();
    });
  }

  void setQuery(String v) {
    _query = InputSanitizer.clean(v);
    notifyListeners();
  }

  void setCategoryFilter(String? id) {
    _categoryFilter = id;
    notifyListeners();
  }

  void sortBy(ProductSortField f) {
    if (_sortField == f) {
      _ascending = !_ascending;
    } else {
      _sortField = f;
      _ascending = true;
    }
    notifyListeners();
  }

  Future<bool> delete(Product p) async {
    final ok = await runAction(() => _products.delete(p.id));
    if (ok) {
      _all = _all.where((e) => e.id != p.id).toList();
      notifyListeners();
    }
    return ok;
  }
}
