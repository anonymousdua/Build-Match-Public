/// All route paths in one place.
class Routes {
  Routes._();

  static const splash = '/splash';
  static const login = '/login';
  static const signup = '/signup';

  // Contractor
  static const contractor = '/contractor';
  static const contractorRfqs = '/contractor/rfqs';
  static const contractorNewRfq = '/contractor/rfqs/new';
  static String contractorRfq(String id) => '/contractor/rfqs/$id';
  static String contractorEditRfq(String id) => '/contractor/rfqs/$id/edit';
  static const contractorSettings = '/contractor/settings';

  // Supplier
  static const supplier = '/supplier';
  static const supplierProducts = '/supplier/products';
  static const supplierNewProduct = '/supplier/products/new';
  static String supplierEditProduct(String id) => '/supplier/products/$id/edit';
  static const supplierMatched = '/supplier/rfqs';
  static String supplierRfq(String id) => '/supplier/rfqs/$id';
  static const supplierBoqs = '/supplier/boqs';
  static const supplierSettings = '/supplier/settings';

  static const publicPaths = {login, signup};
}
