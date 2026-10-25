import '../../models/category.dart';
import '../../models/enums.dart';
import '../../models/quotation.dart';
import '../../models/rfq.dart';
import '../../services/category_repository.dart';
import '../../services/rfq_repository.dart';
import '../base_view_model.dart';

/// Contractor's RFQ detail page: summary, line items, BOQs received,
/// side-by-side comparison, status changes and the hire decision.
class RfqDetailViewModel extends BaseViewModel {
  RfqDetailViewModel(this._rfqs, this._categories, this.rfqId);

  final RfqRepository _rfqs;
  final CategoryRepository _categories;
  final String rfqId;

  RfqDetail? _rfq;
  List<ContractorQuotation> _quotations = const [];
  List<RfqAttachment> _attachments = const [];
  List<Category> _categoryList = const [];
  RevealedContact? lastRevealed;

  RfqDetail? get rfq => _rfq;
  List<ContractorQuotation> get quotations => _quotations;
  List<RfqAttachment> get attachments => _attachments;

  String categoryName(String id) {
    for (final c in _categoryList) {
      if (c.id == id) return c.name;
    }
    return id;
  }

  bool get isDraft => _rfq?.status == RfqStatus.draft;
  bool get isFinal => _rfq?.status.isFinal ?? false;
  bool get canDecide => _rfq?.status.isActive ?? false;
  bool get canEdit => (isDraft || _rfq?.status == RfqStatus.open) && _quotations.isEmpty;
  bool get canDelete => canEdit;

  ContractorQuotation? get accepted {
    for (final q in _quotations) {
      if (q.status == QuotationStatus.accepted) return q;
    }
    return null;
  }

  /// Lowest total among BOQs that are still in play.
  String? get bestPriceId {
    ContractorQuotation? best;
    for (final q in _quotations) {
      if (q.status == QuotationStatus.rejected) continue;
      if (best == null || q.totalAmount < best.totalAmount) best = q;
    }
    return best?.id;
  }

  /// Quotation id with the lowest unit price for an RFQ line (comparison table).
  String? lowestPriceFor(String rfqItemId) {
    String? id;
    double? min;
    for (final q in _quotations) {
      final p = q.lineFor(rfqItemId)?.unitPrice;
      if (p == null) continue;
      if (min == null || p < min) {
        min = p;
        id = q.id;
      }
    }
    return id;
  }

  Future<void> load() async {
    await runLoad(_fetch);
  }

  Future<void> _fetch() async {
    final results = await Future.wait([
      _categories.fetchAll(),
      _rfqs.fetchRfq(rfqId),
      _rfqs.fetchQuotations(rfqId),
      _rfqs.fetchAttachments(rfqId),
    ]);
    _categoryList = results[0] as List<Category>;
    _rfq = results[1] as RfqDetail;
    _quotations = results[2] as List<ContractorQuotation>;
    _attachments = results[3] as List<RfqAttachment>;
  }

  Future<bool> changeStatus(RfqStatus status) async {
    if (_rfq == null || status == _rfq!.status) return true;
    return runAction(() async {
      await _rfqs.updateStatus(rfqId, status);
      await _fetch();
    });
  }

  Future<bool> publish() => changeStatus(RfqStatus.open);

  /// Opening a BOQ marks it "Viewed" for the supplier.
  Future<void> markViewed(ContractorQuotation q) async {
    if (q.status != QuotationStatus.sent) return;
    try {
      await _rfqs.markQuotationViewed(q.id);
      _replace(q.copyWith(status: QuotationStatus.viewed));
    } catch (_) {
      // not critical – the BOQ is still shown
    }
  }

  Future<bool> toggleShortlist(ContractorQuotation q) {
    return runAction(() async {
      final next = await _rfqs.setShortlisted(q.id, q.status != QuotationStatus.shortlisted);
      _replace(q.copyWith(status: next));
    });
  }

  Future<bool> accept(ContractorQuotation q) {
    return runAction(() async {
      lastRevealed = await _rfqs.acceptQuotation(q.id);
      await _fetch(); // statuses of all BOQs + RFQ changed
    });
  }

  Future<bool> reject(ContractorQuotation q) {
    return runAction(() async {
      await _rfqs.rejectQuotation(q.id);
      _replace(q.copyWith(status: QuotationStatus.rejected));
    });
  }

  Future<bool> delete() => runAction(() => _rfqs.deleteRfq(rfqId));

  Future<String?> attachmentUrl(RfqAttachment a) async {
    String? url;
    final ok = await runAction(() async => url = await _rfqs.attachmentUrl(a.storagePath));
    return ok ? url : null;
  }

  void _replace(ContractorQuotation q) {
    _quotations = [for (final e in _quotations) e.id == q.id ? q : e];
    notifyListeners();
  }
}
