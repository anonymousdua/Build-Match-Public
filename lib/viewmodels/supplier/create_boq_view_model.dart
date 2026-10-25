import '../../core/constants/app_constants.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/input_sanitizer.dart';
import '../../models/enums.dart';
import '../../models/matched_rfq.dart';
import '../../models/product.dart';
import '../../models/quotation.dart';
import '../../models/rfq.dart';
import '../../services/product_repository.dart';
import '../../services/quotation_repository.dart';
import '../base_view_model.dart';

/// One row of "Your quotation": an RFQ line plus what the supplier offers.
/// productId == null means "Not supplied" (the line is left out of the BOQ).
class BoqLineDraft {
  BoqLineDraft({required this.item, this.productId, this.quantityText = '', this.unitPriceText = '', this.availability = Availability.inStock, this.deliveryDate});

  final SupplierRfqItem item;
  String? productId;
  String quantityText;
  String unitPriceText;
  Availability availability;
  DateTime? deliveryDate;

  bool get isSupplied => productId != null;
  double? get quantity => InputSanitizer.parseNumber(quantityText);
  double? get unitPrice => InputSanitizer.parseNumber(unitPriceText);

  double? get lineTotal {
    final q = quantity, p = unitPrice;
    if (!isSupplied || q == null || p == null) return null;
    return double.parse((q * p).toStringAsFixed(2));
  }
}

class CreateBoqViewModel extends BaseViewModel {
  CreateBoqViewModel(this._quotes, this._products, this.rfqId);

  final QuotationRepository _quotes;
  final ProductRepository _products;
  final String rfqId;

  SupplierRfq? _rfq;
  List<Product> _myProducts = const [];
  List<RfqAttachment> _attachments = const [];
  List<BoqLineDraft> _lines = const [];

  SupplierRfq? get rfq => _rfq;
  List<BoqLineDraft> get lines => _lines;
  List<RfqAttachment> get attachments => _attachments;
  bool get notFound => !isLoading && loadError == null && _rfq == null;

  DateTime? validUntil;
  String notes = '';
  String? formError;
  QuotationStatus? savedStatus;

  /// Sent BOQs and finished RFQs are read-only.
  bool get readOnly {
    final r = _rfq;
    if (r == null) return true;
    final q = r.myQuotation;
    return !r.status.isActive || (q != null && q.status != QuotationStatus.draft);
  }

  String? get readOnlyReason {
    final r = _rfq;
    if (r == null) return null;
    final q = r.myQuotation;
    if (q != null && q.status != QuotationStatus.draft) {
      return 'BOQ ${q.code} was sent (${q.status.label.toLowerCase()}). It can no longer be edited.';
    }
    if (!r.status.isActive) return 'This RFQ is no longer accepting BOQs.';
    return null;
  }

  /// Products to offer for a line: suggested (matched) first, then the rest
  /// of the same category, then everything else that's active.
  List<Product> productOptionsFor(SupplierRfqItem item) {
    final active = _myProducts.where((p) => p.isActive).toList();
    int rank(Product p) {
      if (item.suggestedProductIds.contains(p.id)) return 0;
      if (p.categoryId == item.categoryId) return 1;
      return 2;
    }

    active.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.name.compareTo(b.name);
    });
    // keep a product that was quoted earlier even if since deactivated
    for (final l in _lines) {
      if (l.item.id == item.id && l.productId != null && !active.any((p) => p.id == l.productId)) {
        final old = _myProducts.where((p) => p.id == l.productId);
        active.insertAll(0, old);
      }
    }
    return active;
  }

  double get grandTotal => _lines.fold<double>(0, (sum, l) => sum + (l.lineTotal ?? 0));
  int get suppliedCount => _lines.where((l) => l.isSupplied).length;

  /// Latest promised line delivery = BOQ delivery date shown to the contractor.
  DateTime? get overallDelivery {
    DateTime? d;
    for (final l in _lines.where((l) => l.isSupplied)) {
      final ld = l.deliveryDate ?? _rfq?.requiredBy;
      if (ld != null && (d == null || ld.isAfter(d))) d = ld;
    }
    return d;
  }

  Future<void> load() async {
    await runLoad(() async {
      final results = await Future.wait<Object?>([
        _quotes.fetchMatchedRfq(rfqId),
        _products.fetchMine(),
        _quotes.fetchAttachments(rfqId),
      ]);
      _rfq = results[0] as SupplierRfq?;
      _myProducts = results[1]! as List<Product>;
      _attachments = results[2]! as List<RfqAttachment>;
      if (_rfq != null) _buildLines(_rfq!);
    });
  }

  void _buildLines(SupplierRfq r) {
    final existing = {for (final l in r.myQuotation?.lines ?? const <QuotationLine>[]) l.rfqItemId: l};
    _lines = r.items.map((item) {
      final q = existing[item.id];
      if (q != null) {
        return BoqLineDraft(
          item: item,
          productId: q.productId ?? (item.suggestedProductIds.isEmpty ? null : item.suggestedProductIds.first),
          quantityText: Fmt.plainNumber(q.quantity),
          unitPriceText: Fmt.plainNumber(q.unitPrice),
          availability: q.availability ?? Availability.inStock,
          deliveryDate: q.deliveryDate,
        );
      }
      return BoqLineDraft(item: item, deliveryDate: r.requiredBy);
    }).toList();
    validUntil = r.myQuotation?.validUntil;
    notes = r.myQuotation?.notes ?? '';
  }

  void selectProduct(BoqLineDraft line, String? productId) {
    line.productId = productId;
    if (productId != null) {
      // sensible defaults: requested quantity and the product's base price
      if (line.quantityText.isEmpty) line.quantityText = Fmt.plainNumber(line.item.quantity);
      if (line.unitPriceText.isEmpty) {
        final p = _myProducts.where((e) => e.id == productId);
        if (p.isNotEmpty && p.first.priceMin != null) line.unitPriceText = Fmt.plainNumber(p.first.priceMin);
      }
      line.deliveryDate ??= _rfq?.requiredBy;
    }
    formError = null;
    notifyListeners();
  }

  void setQuantity(BoqLineDraft line, String v) {
    line.quantityText = v;
    notifyListeners(); // line total
  }

  void setUnitPrice(BoqLineDraft line, String v) {
    line.unitPriceText = v;
    notifyListeners();
  }

  void setAvailability(BoqLineDraft line, Availability a) {
    line.availability = a;
    notifyListeners();
  }

  void setLineDelivery(BoqLineDraft line, DateTime? d) {
    line.deliveryDate = d;
    formError = null;
    notifyListeners();
  }

  void setValidUntil(DateTime? d) {
    validUntil = d;
    notifyListeners();
  }

  // ---- validators ----------------------------------------------------------
  String? validateQuantity(BoqLineDraft l, String? v) => !l.isSupplied
      ? null
      : InputSanitizer.validateNumber(v, field: 'Qty', max: AppLimits.quantityMax);
  String? validateUnitPrice(BoqLineDraft l, String? v) => !l.isSupplied
      ? null
      : InputSanitizer.validateNumber(v, field: 'Price', max: AppLimits.priceMax, maxDecimals: 2);
  String? validateNotes(String? v) =>
      InputSanitizer.validateText(v, field: 'Notes', required: false, max: AppLimits.notesMax, multiline: true);

  bool _validateExtras({required bool send}) {
    formError = null;
    if (send && suppliedCount == 0) {
      formError = 'Choose a product for at least one requested item.';
    } else {
      for (final l in _lines.where((l) => l.isSupplied)) {
        final e = InputSanitizer.validateDate(l.deliveryDate, field: 'Delivery date for ${l.item.itemName}');
        if (e != null) {
          formError = e;
          break;
        }
      }
      if (formError == null && validUntil != null) {
        formError = InputSanitizer.validateDate(validUntil, field: '"Valid until"');
      }
    }
    notifyListeners();
    return formError == null;
  }

  Future<bool> save({required bool send, required bool formValid}) async {
    if (readOnly) return false;
    if (!_validateExtras(send: send) || !formValid) return false;

    final supplied = _lines.where((l) => l.isSupplied).toList();
    final input = QuotationInput(
      rfqId: rfqId,
      lines: supplied
          .map((l) => QuotationLineInput(
                rfqItemId: l.item.id,
                productId: l.productId,
                quantity: l.quantity!,
                unitPrice: l.unitPrice!,
                availability: l.availability,
                deliveryDate: l.deliveryDate,
              ))
          .toList(),
      deliveryDate: overallDelivery ?? _rfq!.requiredBy,
      validUntil: validUntil,
      notes: InputSanitizer.cleanOrNull(notes, multiline: true),
    );

    return runAction(() async {
      await _quotes.submit(input, send: send);
      savedStatus = send ? QuotationStatus.sent : QuotationStatus.draft;
      // reload so read-only state / BOQ code reflect the server
      final fresh = await _quotes.fetchMatchedRfq(rfqId);
      if (fresh != null) {
        _rfq = fresh;
        _buildLines(fresh);
      }
    });
  }

  Future<String?> attachmentUrl(RfqAttachment a) async {
    String? url;
    final ok = await runAction(() async => url = await _quotes.attachmentUrl(a.storagePath));
    return ok ? url : null;
  }
}
