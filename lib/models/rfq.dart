import '../core/utils/formatters.dart';
import 'enums.dart';

/// Row of `get_my_rfqs()` – contractor RFQ list with counts.
class RfqSummary {
  const RfqSummary({
    required this.id,
    required this.code,
    required this.title,
    required this.deliveryLocation,
    required this.requiredBy,
    required this.status,
    required this.createdAt,
    required this.itemCount,
    required this.boqCount,
    required this.matchedSupplierCount,
    this.description,
    this.publishedAt,
  });

  final String id;
  final String code; // RFQ-2041
  final String title;
  final String? description;
  final String deliveryLocation;
  final DateTime requiredBy;
  final RfqStatus status;
  final DateTime createdAt;
  final DateTime? publishedAt;
  final int itemCount;
  final int boqCount;
  final int matchedSupplierCount;

  factory RfqSummary.fromJson(Map<String, dynamic> json) => RfqSummary(
        id: json['id'] as String,
        code: json['rfq_code'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        deliveryLocation: json['delivery_location'] as String,
        requiredBy: Fmt.parseDate(json['required_by'])!,
        status: RfqStatus.fromDb(json['status'] as String?),
        createdAt: Fmt.parseDate(json['created_at'])!,
        publishedAt: Fmt.parseDate(json['published_at']),
        itemCount: Fmt.parseInt(json['item_count']),
        boqCount: Fmt.parseInt(json['boq_count']),
        matchedSupplierCount: Fmt.parseInt(json['matched_supplier_count']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'rfq_code': code,
        'title': title,
        'description': description,
        'delivery_location': deliveryLocation,
        'required_by': Fmt.isoDate(requiredBy),
        'status': status.dbValue,
        'created_at': createdAt.toIso8601String(),
        'published_at': publishedAt?.toIso8601String(),
        'item_count': itemCount,
        'boq_count': boqCount,
        'matched_supplier_count': matchedSupplierCount,
      };
}

/// One RFQ line item (`rfq_items`).
class RfqItem {
  const RfqItem({
    required this.id,
    required this.lineNo,
    required this.itemName,
    required this.categoryId,
    required this.quantity,
    required this.unit,
    this.specification,
  });

  final String id;
  final int lineNo;
  final String itemName;
  final String categoryId;
  final String? specification;
  final double quantity;
  final UnitType unit;

  factory RfqItem.fromJson(Map<String, dynamic> json) => RfqItem(
        id: json['id'] as String,
        lineNo: Fmt.parseInt(json['line_no']),
        itemName: json['item_name'] as String,
        categoryId: json['category_id'] as String,
        specification: json['specification'] as String?,
        quantity: Fmt.parseDouble(json['quantity']) ?? 0,
        unit: UnitType.fromDb(json['unit'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'line_no': lineNo,
        'item_name': itemName,
        'category_id': categoryId,
        'specification': specification,
        'quantity': quantity,
        'unit': unit.dbValue,
      };
}

/// Contractor's full view of their own RFQ (`rfqs` + `rfq_items`).
class RfqDetail {
  const RfqDetail({
    required this.id,
    required this.refNo,
    required this.title,
    required this.deliveryLocation,
    required this.requiredBy,
    required this.status,
    required this.createdAt,
    required this.items,
    this.description,
    this.hiredQuotationId,
  });

  final String id;
  final int refNo;
  final String title;
  final String? description;
  final String deliveryLocation;
  final DateTime requiredBy;
  final RfqStatus status;
  final DateTime createdAt;
  final String? hiredQuotationId;
  final List<RfqItem> items;

  String get code => 'RFQ-$refNo';

  factory RfqDetail.fromJson(Map<String, dynamic> json) {
    final items = ((json['rfq_items'] as List?) ?? const [])
        .map((e) => RfqItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => a.lineNo.compareTo(b.lineNo));
    return RfqDetail(
      id: json['id'] as String,
      refNo: Fmt.parseInt(json['ref_no']),
      title: json['title'] as String,
      description: json['description'] as String?,
      deliveryLocation: json['delivery_location'] as String,
      requiredBy: Fmt.parseDate(json['required_by'])!,
      status: RfqStatus.fromDb(json['status'] as String?),
      createdAt: Fmt.parseDate(json['created_at'])!,
      hiredQuotationId: json['hired_quotation_id'] as String?,
      items: items,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'ref_no': refNo,
        'title': title,
        'description': description,
        'delivery_location': deliveryLocation,
        'required_by': Fmt.isoDate(requiredBy),
        'status': status.dbValue,
        'created_at': createdAt.toIso8601String(),
        'hired_quotation_id': hiredQuotationId,
        'rfq_items': items.map((e) => e.toJson()).toList(),
      };
}

/// Line item being edited on the Create RFQ form (sent to `save_rfq`).
class RfqItemInput {
  const RfqItemInput({
    required this.itemName,
    required this.categoryId,
    required this.quantity,
    required this.unit,
    this.specification,
  });

  final String itemName;
  final String categoryId;
  final String? specification;
  final double quantity;
  final UnitType unit;

  Map<String, dynamic> toJson() => {
        'item_name': itemName,
        'category_id': categoryId,
        'specification': specification,
        'quantity': quantity,
        'unit': unit.dbValue,
      };
}

class RfqInput {
  const RfqInput({
    required this.title,
    required this.deliveryLocation,
    required this.requiredBy,
    required this.items,
    this.description,
  });

  final String title;
  final String? description;
  final String deliveryLocation;
  final DateTime requiredBy;
  final List<RfqItemInput> items;
}

/// Dashboard stat cards (`get_contractor_stats()`).
class ContractorStats {
  const ContractorStats({
    this.totalRfqs = 0,
    this.openRfqs = 0,
    this.boqsReceived = 0,
    this.boqsThisWeek = 0,
    this.hiredRfqs = 0,
  });

  final int totalRfqs;
  final int openRfqs;
  final int boqsReceived;
  final int boqsThisWeek;
  final int hiredRfqs;

  factory ContractorStats.fromJson(Map<String, dynamic> json) => ContractorStats(
        totalRfqs: Fmt.parseInt(json['total_rfqs']),
        openRfqs: Fmt.parseInt(json['open_rfqs']),
        boqsReceived: Fmt.parseInt(json['boqs_received']),
        boqsThisWeek: Fmt.parseInt(json['boqs_this_week']),
        hiredRfqs: Fmt.parseInt(json['hired_rfqs']),
      );

  Map<String, dynamic> toJson() => {
        'total_rfqs': totalRfqs,
        'open_rfqs': openRfqs,
        'boqs_received': boqsReceived,
        'boqs_this_week': boqsThisWeek,
        'hired_rfqs': hiredRfqs,
      };
}

/// File attached to an RFQ (`rfq_attachments`).
class RfqAttachment {
  const RfqAttachment({
    required this.id,
    required this.rfqId,
    required this.storagePath,
    required this.fileName,
    required this.sizeBytes,
    required this.mimeType,
  });

  final String id;
  final String rfqId;
  final String storagePath;
  final String fileName;
  final int sizeBytes;
  final String mimeType;

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(sizeBytes / 1024).ceil()} KB';
  }

  factory RfqAttachment.fromJson(Map<String, dynamic> json) => RfqAttachment(
        id: json['id'] as String,
        rfqId: json['rfq_id'] as String,
        storagePath: json['storage_path'] as String,
        fileName: json['file_name'] as String,
        sizeBytes: Fmt.parseInt(json['size_bytes']),
        mimeType: json['mime_type'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'rfq_id': rfqId,
        'storage_path': storagePath,
        'file_name': fileName,
        'size_bytes': sizeBytes,
        'mime_type': mimeType,
      };
}
