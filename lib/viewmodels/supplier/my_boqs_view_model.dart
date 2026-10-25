import '../../models/quotation.dart';
import '../../services/quotation_repository.dart';
import '../base_view_model.dart';

class MyBoqsViewModel extends BaseViewModel {
  MyBoqsViewModel(this._quotes);
  final QuotationRepository _quotes;

  List<SupplierQuotation> _items = const [];
  List<SupplierQuotation> get items => _items;

  Future<void> load() async {
    await runLoad(() async => _items = await _quotes.fetchMyQuotations());
  }
}
