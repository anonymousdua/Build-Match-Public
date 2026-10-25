import '../../models/rfq.dart';
import '../../services/rfq_repository.dart';
import '../base_view_model.dart';

class ContractorDashboardViewModel extends BaseViewModel {
  ContractorDashboardViewModel(this._rfqs);
  final RfqRepository _rfqs;

  ContractorStats _stats = const ContractorStats();
  List<RfqSummary> _recent = const [];

  ContractorStats get stats => _stats;
  List<RfqSummary> get recent => _recent;

  Future<void> load() async {
    await runLoad(() async {
      final results = await Future.wait([_rfqs.fetchStats(), _rfqs.fetchMyRfqs()]);
      _stats = results[0] as ContractorStats;
      _recent = (results[1] as List<RfqSummary>).take(5).toList();
    });
  }
}
