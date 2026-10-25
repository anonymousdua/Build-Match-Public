import '../../models/matched_rfq.dart';
import '../../services/quotation_repository.dart';
import '../base_view_model.dart';

class SupplierDashboardViewModel extends BaseViewModel {
  SupplierDashboardViewModel(this._quotes);
  final QuotationRepository _quotes;

  SupplierStats _stats = const SupplierStats();
  List<MatchedRfq> _newest = const [];

  SupplierStats get stats => _stats;
  List<MatchedRfq> get newest => _newest;

  Future<void> load() async {
    await runLoad(() async {
      final results = await Future.wait([_quotes.fetchStats(), _quotes.fetchMatchedRfqs()]);
      _stats = results[0] as SupplierStats;
      _newest = (results[1] as List<MatchedRfq>).where((m) => m.rfqStatus.isActive).take(5).toList();
    });
  }
}
