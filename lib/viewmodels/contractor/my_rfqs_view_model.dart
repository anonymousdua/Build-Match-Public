import '../../core/utils/input_sanitizer.dart';
import '../../models/enums.dart';
import '../../models/rfq.dart';
import '../../services/rfq_repository.dart';
import '../base_view_model.dart';

enum RfqSortField { code, title, created, requiredBy, status }

class MyRfqsViewModel extends BaseViewModel {
  MyRfqsViewModel(this._rfqs, {String? initialQuery}) : _query = InputSanitizer.clean(initialQuery);
  final RfqRepository _rfqs;

  List<RfqSummary> _all = const [];
  String _query;
  RfqStatus? _statusFilter;
  RfqSortField _sortField = RfqSortField.created;
  bool _ascending = false;

  String get query => _query;
  RfqStatus? get statusFilter => _statusFilter;
  RfqSortField get sortField => _sortField;
  bool get ascending => _ascending;
  bool get hasAny => _all.isNotEmpty;

  /// Search + status filter + sort, applied client-side.
  List<RfqSummary> get visible {
    final q = _query.toLowerCase();
    final list = _all.where((r) {
      if (_statusFilter != null && r.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      return r.title.toLowerCase().contains(q) ||
          r.code.toLowerCase().contains(q) ||
          r.deliveryLocation.toLowerCase().contains(q);
    }).toList();

    int cmp(RfqSummary a, RfqSummary b) {
      switch (_sortField) {
        case RfqSortField.code:
          return a.code.compareTo(b.code);
        case RfqSortField.title:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case RfqSortField.created:
          return a.createdAt.compareTo(b.createdAt);
        case RfqSortField.requiredBy:
          return a.requiredBy.compareTo(b.requiredBy);
        case RfqSortField.status:
          return a.status.index.compareTo(b.status.index);
      }
    }

    list.sort((a, b) => _ascending ? cmp(a, b) : cmp(b, a));
    return list;
  }

  Future<void> load() async {
    await runLoad(() async => _all = await _rfqs.fetchMyRfqs());
  }

  void setQuery(String value) {
    _query = InputSanitizer.clean(value);
    notifyListeners();
  }

  void setStatusFilter(RfqStatus? status) {
    _statusFilter = status;
    notifyListeners();
  }

  void sortBy(RfqSortField field) {
    if (_sortField == field) {
      _ascending = !_ascending;
    } else {
      _sortField = field;
      _ascending = field == RfqSortField.title || field == RfqSortField.code;
    }
    notifyListeners();
  }
}
