import '../../core/utils/input_sanitizer.dart';
import '../../models/matched_rfq.dart';
import '../../services/quotation_repository.dart';
import '../base_view_model.dart';

class MatchedRfqsViewModel extends BaseViewModel {
  MatchedRfqsViewModel(this._quotes, {String? initialQuery}) : _query = InputSanitizer.clean(initialQuery);
  final QuotationRepository _quotes;

  List<MatchedRfq> _all = const [];
  String _query;

  String get query => _query;
  bool get hasAny => _all.isNotEmpty;

  /// Best matches first, then newest.
  List<MatchedRfq> get visible {
    final q = _query.toLowerCase();
    final list = _all
        .where((m) =>
            q.isEmpty ||
            m.title.toLowerCase().contains(q) ||
            m.rfqCode.toLowerCase().contains(q) ||
            m.deliveryLocation.toLowerCase().contains(q) ||
            m.contractorAlias.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        final s = b.matchScore.compareTo(a.matchScore);
        return s != 0 ? s : b.matchedAt.compareTo(a.matchedAt);
      });
    return list;
  }

  Future<void> load() async {
    await runLoad(() async => _all = await _quotes.fetchMatchedRfqs());
  }

  void setQuery(String v) {
    _query = InputSanitizer.clean(v);
    notifyListeners();
  }
}
