import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/formatters.dart';
import '../models/matched_rfq.dart';
import '../models/quotation.dart';
import '../models/rfq.dart';
import 'supabase_service.dart';

/// Everything a SUPPLIER does with matched RFQs and their own BOQs.
/// Contractor identity is never returned by these calls (aliases only)
/// until the supplier's BOQ has been accepted.
abstract class QuotationRepository {
  Future<SupplierStats> fetchStats();
  Future<List<MatchedRfq>> fetchMatchedRfqs();

  /// Returns null when the RFQ doesn't exist or isn't matched to you.
  Future<SupplierRfq?> fetchMatchedRfq(String rfqId);
  Future<List<RfqAttachment>> fetchAttachments(String rfqId);
  Future<String> attachmentUrl(String storagePath);

  /// Saves (send = false) or sends (send = true) the BOQ. Returns its id.
  Future<String> submit(QuotationInput input, {required bool send});
  Future<List<SupplierQuotation>> fetchMyQuotations();
}

class SupabaseQuotationRepository implements QuotationRepository {
  SupabaseQuotationRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<SupplierStats> fetchStats() async {
    final res = await _client.rpc('get_supplier_stats');
    return SupplierStats.fromJson(rpcFirstRow(res));
  }

  @override
  Future<List<MatchedRfq>> fetchMatchedRfqs() async {
    final res = await _client.rpc('get_matched_rfqs');
    return rpcRows(res).map(MatchedRfq.fromJson).toList();
  }

  @override
  Future<SupplierRfq?> fetchMatchedRfq(String rfqId) async {
    final res = await _client.rpc('get_supplier_rfq', params: {'p_rfq_id': rfqId});
    if (res == null) return null;
    return SupplierRfq.fromJson(Map<String, dynamic>.from(res as Map));
  }

  @override
  Future<List<RfqAttachment>> fetchAttachments(String rfqId) async {
    // RLS allows matched suppliers to read attachment metadata (no user ids in it).
    final rows = await _client
        .from('rfq_attachments')
        .select('id, rfq_id, storage_path, file_name, size_bytes, mime_type')
        .eq('rfq_id', rfqId)
        .order('created_at');
    return rows.map(RfqAttachment.fromJson).toList();
  }

  @override
  Future<String> attachmentUrl(String storagePath) =>
      _client.storage.from('rfq-attachments').createSignedUrl(storagePath, 600);

  @override
  Future<String> submit(QuotationInput input, {required bool send}) async {
    final res = await _client.rpc('submit_quotation', params: {
      'p_rfq_id': input.rfqId,
      'p_items': input.lines.map((e) => e.toJson()).toList(),
      'p_delivery_date': Fmt.isoDate(input.deliveryDate),
      'p_valid_until': input.validUntil == null ? null : Fmt.isoDate(input.validUntil!),
      'p_notes': input.notes,
      'p_send': send,
    });
    return res as String;
  }

  @override
  Future<List<SupplierQuotation>> fetchMyQuotations() async {
    final res = await _client.rpc('get_my_quotations');
    return rpcRows(res).map(SupplierQuotation.fromJson).toList();
  }
}
