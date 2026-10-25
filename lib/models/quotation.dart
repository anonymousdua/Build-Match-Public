import '../core/utils/formatters.dart';
import 'enums.dart';

/// One priced line of a BOQ as returned by the RPCs. For supplier views every
/// RFQ line is included; [isSupplied] is false for "Not supplied" lines.
class QuotationLine {
  const QuotationLine({
    required this.rfqItemId,
    this.itemName,
    this.unit,
    this.requestedQuantity,
    this.productId,
    this.productName,
    this.quantity,
    this.unitPrice,
    this.lineTotal,
    this.availability,
    this.deliveryDate,
  });

  final String rfqItemId;
  final String? itemName;
  final UnitType? unit;
  final double? requestedQuantity;
  final String? productId;
  final String? productName;
  final double? quantity;
  final double? unitPrice;
  final double? lineTotal;
  final Availability? availability;
  final DateTime? deliveryDate;

  bool get isSupplied => unitPrice != null;

  factory QuotationLine.fromJson(Map<String, dynamic> json) => QuotationLine(
        rfqItemId: json['rfq_item_id'] as String,
        itemName: json['item_name'] as String?,
        unit: json['unit'] == null ? null : UnitType.fromDb(json['unit'] as String?),
        requestedQuantity: Fmt.parseDouble(json['requested_quantity']),
        productId: json['product_id'] as String?,
        productName: json['product_name'] as String?,
        quantity: Fmt.parseDouble(json['quantity']),
        unitPrice: Fmt.parseDouble(json['unit_price']),
        lineTotal: Fmt.parseDouble(json['line_total']),
        availability: json['availability'] == null ? null : Availability.fromDb(json['availability'] as String?),
        deliveryDate: Fmt.parseDate(json['delivery_date']),
      );

  Map<String, dynamic> toJson() => {
        'rfq_item_id': rfqItemId,
        'item_name': itemName,
        'unit': unit?.dbValue,
        'requested_quantity': requestedQuantity,
        'product_id': productId,
        'product_name': productName,
        'quantity': quantity,
        'unit_price': unitPrice,
        'line_total': lineTotal,
        'availability': availability?.dbValue,
        'delivery_date': deliveryDate == null ? null : Fmt.isoDate(deliveryDate!),
      };
}

List<QuotationLine> _lines(Object? v) => ((v as List?) ?? const [])
    .map((e) => QuotationLine.fromJson(Map<String, dynamic>.from(e as Map)))
    .toList();

/// A BOQ as the CONTRACTOR sees it (`get_rfq_quotations`). Supplier identity
/// fields are only filled after acceptance.
class ContractorQuotation {
  const ContractorQuotation({
    required this.id,
    required this.code,
    required this.supplierAlias,
    required this.status,
    required this.totalAmount,
    required this.coveredItems,
    required this.totalItems,
    required this.lines,
    required this.isRevealed,
    this.deliveryDate,
    this.validUntil,
    this.notes,
    this.sentAt,
    this.supplierCompanyName,
    this.supplierEmail,
  });

  final String id;
  final String code;
  final String supplierAlias; // 'Supplier #S-1093'
  final QuotationStatus status;
  final double totalAmount;
  final DateTime? deliveryDate;
  final DateTime? validUntil;
  final String? notes;
  final DateTime? sentAt;
  final int coveredItems;
  final int totalItems;
  final List<QuotationLine> lines;
  final bool isRevealed;
  final String? supplierCompanyName;
  final String? supplierEmail;

  /// '#S-1093'
  String get shortAlias {
    final i = supplierAlias.indexOf('#');
    return i >= 0 ? supplierAlias.substring(i) : supplierAlias;
  }

  QuotationLine? lineFor(String rfqItemId) {
    for (final l in lines) {
      if (l.rfqItemId == rfqItemId) return l;
    }
    return null;
  }

  ContractorQuotation copyWith({QuotationStatus? status}) => ContractorQuotation(
        id: id,
        code: code,
        supplierAlias: supplierAlias,
        status: status ?? this.status,
        totalAmount: totalAmount,
        coveredItems: coveredItems,
        totalItems: totalItems,
        lines: lines,
        isRevealed: isRevealed,
        deliveryDate: deliveryDate,
        validUntil: validUntil,
        notes: notes,
        sentAt: sentAt,
        supplierCompanyName: supplierCompanyName,
        supplierEmail: supplierEmail,
      );

  factory ContractorQuotation.fromJson(Map<String, dynamic> json) => ContractorQuotation(
        id: json['quotation_id'] as String,
        code: json['boq_code'] as String,
        supplierAlias: json['supplier_alias'] as String,
        status: QuotationStatus.fromDb(json['status'] as String?),
        totalAmount: Fmt.parseDouble(json['total_amount']) ?? 0,
        deliveryDate: Fmt.parseDate(json['delivery_date']),
        validUntil: Fmt.parseDate(json['valid_until']),
        notes: json['notes'] as String?,
        sentAt: Fmt.parseDate(json['sent_at']),
        coveredItems: Fmt.parseInt(json['covered_items']),
        totalItems: Fmt.parseInt(json['total_items']),
        lines: _lines(json['items']),
        isRevealed: json['is_revealed'] as bool? ?? false,
        supplierCompanyName: json['supplier_company_name'] as String?,
        supplierEmail: json['supplier_email'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'quotation_id': id,
        'boq_code': code,
        'supplier_alias': supplierAlias,
        'status': status.dbValue,
        'total_amount': totalAmount,
        'delivery_date': deliveryDate == null ? null : Fmt.isoDate(deliveryDate!),
        'valid_until': validUntil == null ? null : Fmt.isoDate(validUntil!),
        'notes': notes,
        'sent_at': sentAt?.toIso8601String(),
        'covered_items': coveredItems,
        'total_items': totalItems,
        'items': lines.map((e) => e.toJson()).toList(),
        'is_revealed': isRevealed,
        'supplier_company_name': supplierCompanyName,
        'supplier_email': supplierEmail,
      };
}

/// A BOQ as the SUPPLIER sees it (`get_my_quotations`).
class SupplierQuotation {
  const SupplierQuotation({
    required this.id,
    required this.code,
    required this.rfqId,
    required this.rfqCode,
    required this.rfqTitle,
    required this.contractorAlias,
    required this.status,
    required this.totalAmount,
    required this.createdAt,
    required this.lines,
    required this.isRevealed,
    this.deliveryDate,
    this.validUntil,
    this.notes,
    this.sentAt,
    this.contractorCompanyName,
    this.contractorEmail,
  });

  final String id;
  final String code;
  final String rfqId;
  final String rfqCode;
  final String rfqTitle;
  final String contractorAlias;
  final QuotationStatus status;
  final double totalAmount;
  final DateTime? deliveryDate;
  final DateTime? validUntil;
  final String? notes;
  final DateTime? sentAt;
  final DateTime createdAt;
  final List<QuotationLine> lines;
  final bool isRevealed;
  final String? contractorCompanyName;
  final String? contractorEmail;

  factory SupplierQuotation.fromJson(Map<String, dynamic> json) => SupplierQuotation(
        id: json['quotation_id'] as String,
        code: json['boq_code'] as String,
        rfqId: json['rfq_id'] as String,
        rfqCode: json['rfq_code'] as String,
        rfqTitle: json['rfq_title'] as String,
        contractorAlias: json['contractor_alias'] as String,
        status: QuotationStatus.fromDb(json['status'] as String?),
        totalAmount: Fmt.parseDouble(json['total_amount']) ?? 0,
        deliveryDate: Fmt.parseDate(json['delivery_date']),
        validUntil: Fmt.parseDate(json['valid_until']),
        notes: json['notes'] as String?,
        sentAt: Fmt.parseDate(json['sent_at']),
        createdAt: Fmt.parseDate(json['created_at'])!,
        lines: _lines(json['items']),
        isRevealed: json['is_revealed'] as bool? ?? false,
        contractorCompanyName: json['contractor_company_name'] as String?,
        contractorEmail: json['contractor_email'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'quotation_id': id,
        'boq_code': code,
        'rfq_id': rfqId,
        'rfq_code': rfqCode,
        'rfq_title': rfqTitle,
        'contractor_alias': contractorAlias,
        'status': status.dbValue,
        'total_amount': totalAmount,
        'delivery_date': deliveryDate == null ? null : Fmt.isoDate(deliveryDate!),
        'valid_until': validUntil == null ? null : Fmt.isoDate(validUntil!),
        'notes': notes,
        'sent_at': sentAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'items': lines.map((e) => e.toJson()).toList(),
        'is_revealed': isRevealed,
        'contractor_company_name': contractorCompanyName,
        'contractor_email': contractorEmail,
      };
}

/// One line typed into the Create BOQ form (sent to `submit_quotation`).
class QuotationLineInput {
  const QuotationLineInput({
    required this.rfqItemId,
    required this.quantity,
    required this.unitPrice,
    required this.availability,
    this.productId,
    this.deliveryDate,
  });

  final String rfqItemId;
  final String? productId;
  final double quantity;
  final double unitPrice;
  final Availability availability;
  final DateTime? deliveryDate;

  Map<String, dynamic> toJson() => {
        'rfq_item_id': rfqItemId,
        'product_id': productId,
        'quantity': quantity,
        'unit_price': unitPrice,
        'availability': availability.dbValue,
        'delivery_date': deliveryDate == null ? null : Fmt.isoDate(deliveryDate!),
      };
}

class QuotationInput {
  const QuotationInput({
    required this.rfqId,
    required this.lines,
    required this.deliveryDate,
    this.validUntil,
    this.notes,
  });

  final String rfqId;
  final List<QuotationLineInput> lines;
  final DateTime deliveryDate;
  final DateTime? validUntil;
  final String? notes;
}

/// Contact details unlocked after a BOQ is accepted.
class RevealedContact {
  const RevealedContact({required this.companyName, this.email, this.alias});

  final String companyName;
  final String? email;
  final String? alias;

  factory RevealedContact.fromJson(Map<String, dynamic> json) => RevealedContact(
        companyName: (json['company_name'] ?? json['supplier_company_name']) as String,
        email: (json['email'] ?? json['supplier_email']) as String?,
        alias: json['supplier_alias'] as String?,
      );

  Map<String, dynamic> toJson() => {'company_name': companyName, 'email': email, 'alias': alias};
}
