import '../core/utils/formatters.dart';
import 'enums.dart';
import 'quotation.dart';

/// Row of `get_matched_rfqs()` – what a supplier sees in "Matched RFQs".
class MatchedRfq {
  const MatchedRfq({
    required this.rfqId,
    required this.rfqCode,
    required this.title,
    required this.deliveryLocation,
    required this.requiredBy,
    required this.rfqStatus,
    required this.contractorAlias,
    required this.itemCount,
    required this.matchScore,
    required this.matchedAt,
    this.quotationId,
    this.quotationStatus,
  });

  final String rfqId;
  final String rfqCode;
  final String title;
  final String deliveryLocation;
  final DateTime requiredBy;
  final RfqStatus rfqStatus;
  final String contractorAlias;
  final int itemCount;
  final double matchScore;
  final DateTime matchedAt;
  final String? quotationId;
  final QuotationStatus? quotationStatus;

  bool get hasSentBoq => quotationStatus != null && quotationStatus != QuotationStatus.draft;
  bool get hasDraftBoq => quotationStatus == QuotationStatus.draft;
  bool get canQuote => rfqStatus.isActive && !hasSentBoq;

  factory MatchedRfq.fromJson(Map<String, dynamic> json) => MatchedRfq(
        rfqId: json['rfq_id'] as String,
        rfqCode: json['rfq_code'] as String,
        title: json['title'] as String,
        deliveryLocation: json['delivery_location'] as String,
        requiredBy: Fmt.parseDate(json['required_by'])!,
        rfqStatus: RfqStatus.fromDb(json['rfq_status'] as String?),
        contractorAlias: json['contractor_alias'] as String,
        itemCount: Fmt.parseInt(json['item_count']),
        matchScore: Fmt.parseDouble(json['match_score']) ?? 0,
        matchedAt: Fmt.parseDate(json['matched_at'])!,
        quotationId: json['quotation_id'] as String?,
        quotationStatus: json['quotation_status'] == null
            ? null
            : QuotationStatus.fromDb(json['quotation_status'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'rfq_id': rfqId,
        'rfq_code': rfqCode,
        'title': title,
        'delivery_location': deliveryLocation,
        'required_by': Fmt.isoDate(requiredBy),
        'rfq_status': rfqStatus.dbValue,
        'contractor_alias': contractorAlias,
        'item_count': itemCount,
        'match_score': matchScore,
        'matched_at': matchedAt.toIso8601String(),
        'quotation_id': quotationId,
        'quotation_status': quotationStatus?.dbValue,
      };
}

/// RFQ line as the supplier sees it, with products of theirs that matched.
class SupplierRfqItem {
  const SupplierRfqItem({
    required this.id,
    required this.lineNo,
    required this.itemName,
    required this.categoryId,
    required this.quantity,
    required this.unit,
    required this.suggestedProductIds,
    this.specification,
  });

  final String id;
  final int lineNo;
  final String itemName;
  final String categoryId;
  final String? specification;
  final double quantity;
  final UnitType unit;
  final List<String> suggestedProductIds;

  factory SupplierRfqItem.fromJson(Map<String, dynamic> json) => SupplierRfqItem(
        id: json['id'] as String,
        lineNo: Fmt.parseInt(json['line_no']),
        itemName: json['item_name'] as String,
        categoryId: json['category_id'] as String,
        specification: json['specification'] as String?,
        quantity: Fmt.parseDouble(json['quantity']) ?? 0,
        unit: UnitType.fromDb(json['unit'] as String?),
        suggestedProductIds:
            ((json['suggested_product_ids'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'line_no': lineNo,
        'item_name': itemName,
        'category_id': categoryId,
        'specification': specification,
        'quantity': quantity,
        'unit': unit.dbValue,
        'suggested_product_ids': suggestedProductIds,
      };
}

/// The supplier's own BOQ for an RFQ, embedded in [SupplierRfq].
class SupplierOwnQuotation {
  const SupplierOwnQuotation({
    required this.id,
    required this.code,
    required this.status,
    required this.totalAmount,
    required this.lines,
    this.deliveryDate,
    this.validUntil,
    this.notes,
  });

  final String id;
  final String code;
  final QuotationStatus status;
  final double totalAmount;
  final DateTime? deliveryDate;
  final DateTime? validUntil;
  final String? notes;
  final List<QuotationLine> lines;

  factory SupplierOwnQuotation.fromJson(Map<String, dynamic> json) => SupplierOwnQuotation(
        id: json['id'] as String,
        code: json['boq_code'] as String,
        status: QuotationStatus.fromDb(json['status'] as String?),
        totalAmount: Fmt.parseDouble(json['total_amount']) ?? 0,
        deliveryDate: Fmt.parseDate(json['delivery_date']),
        validUntil: Fmt.parseDate(json['valid_until']),
        notes: json['notes'] as String?,
        lines: ((json['items'] as List?) ?? const [])
            .map((e) => QuotationLine.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'boq_code': code,
        'status': status.dbValue,
        'total_amount': totalAmount,
        'delivery_date': deliveryDate == null ? null : Fmt.isoDate(deliveryDate!),
        'valid_until': validUntil == null ? null : Fmt.isoDate(validUntil!),
        'notes': notes,
        'items': lines.map((e) => e.toJson()).toList(),
      };
}

/// `get_supplier_rfq(id)` – one matched RFQ for the Create BOQ page.
class SupplierRfq {
  const SupplierRfq({
    required this.rfqId,
    required this.rfqCode,
    required this.title,
    required this.deliveryLocation,
    required this.requiredBy,
    required this.status,
    required this.contractorAlias,
    required this.matchScore,
    required this.items,
    this.description,
    this.myQuotation,
    this.revealedContact,
  });

  final String rfqId;
  final String rfqCode;
  final String title;
  final String? description;
  final String deliveryLocation;
  final DateTime requiredBy;
  final RfqStatus status;
  final String contractorAlias;
  final double matchScore;
  final List<SupplierRfqItem> items;
  final SupplierOwnQuotation? myQuotation;
  final RevealedContact? revealedContact;

  factory SupplierRfq.fromJson(Map<String, dynamic> json) => SupplierRfq(
        rfqId: json['rfq_id'] as String,
        rfqCode: json['rfq_code'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        deliveryLocation: json['delivery_location'] as String,
        requiredBy: Fmt.parseDate(json['required_by'])!,
        status: RfqStatus.fromDb(json['status'] as String?),
        contractorAlias: json['contractor_alias'] as String,
        matchScore: Fmt.parseDouble(json['match_score']) ?? 0,
        items: ((json['items'] as List?) ?? const [])
            .map((e) => SupplierRfqItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()
          ..sort((a, b) => a.lineNo.compareTo(b.lineNo)),
        myQuotation: json['my_quotation'] == null
            ? null
            : SupplierOwnQuotation.fromJson(Map<String, dynamic>.from(json['my_quotation'] as Map)),
        revealedContact: json['revealed_contact'] == null
            ? null
            : RevealedContact.fromJson(Map<String, dynamic>.from(json['revealed_contact'] as Map)),
      );

  Map<String, dynamic> toJson() => {
        'rfq_id': rfqId,
        'rfq_code': rfqCode,
        'title': title,
        'description': description,
        'delivery_location': deliveryLocation,
        'required_by': Fmt.isoDate(requiredBy),
        'status': status.dbValue,
        'contractor_alias': contractorAlias,
        'match_score': matchScore,
        'items': items.map((e) => e.toJson()).toList(),
        'my_quotation': myQuotation?.toJson(),
        'revealed_contact': revealedContact?.toJson(),
      };
}

/// Supplier dashboard stat cards (`get_supplier_stats()`).
class SupplierStats {
  const SupplierStats({
    this.totalProducts = 0,
    this.matchedRfqs = 0,
    this.matchedLast24h = 0,
    this.boqsSent = 0,
    this.boqsAccepted = 0,
  });

  final int totalProducts;
  final int matchedRfqs;
  final int matchedLast24h;
  final int boqsSent;
  final int boqsAccepted;

  factory SupplierStats.fromJson(Map<String, dynamic> json) => SupplierStats(
        totalProducts: Fmt.parseInt(json['total_products']),
        matchedRfqs: Fmt.parseInt(json['matched_rfqs']),
        matchedLast24h: Fmt.parseInt(json['matched_last_24h']),
        boqsSent: Fmt.parseInt(json['boqs_sent']),
        boqsAccepted: Fmt.parseInt(json['boqs_accepted']),
      );

  Map<String, dynamic> toJson() => {
        'total_products': totalProducts,
        'matched_rfqs': matchedRfqs,
        'matched_last_24h': matchedLast24h,
        'boqs_sent': boqsSent,
        'boqs_accepted': boqsAccepted,
      };
}
