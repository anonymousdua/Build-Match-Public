import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../models/enums.dart';
import '../models/quotation.dart';
import '../models/rfq.dart';
import 'supabase_service.dart';

/// Everything a CONTRACTOR does with RFQs and the BOQs they receive.
abstract class RfqRepository {
  Future<List<RfqSummary>> fetchMyRfqs();
  Future<ContractorStats> fetchStats();
  Future<RfqDetail> fetchRfq(String rfqId);

  /// Creates (rfqId == null) or updates a draft/open RFQ. Returns its id.
  Future<String> saveRfq(RfqInput input, {required bool publish, String? rfqId});
  Future<void> updateStatus(String rfqId, RfqStatus status);
  Future<void> deleteRfq(String rfqId);

  Future<List<ContractorQuotation>> fetchQuotations(String rfqId);
  Future<void> markQuotationViewed(String quotationId);
  Future<QuotationStatus> setShortlisted(String quotationId, bool shortlisted);
  Future<RevealedContact> acceptQuotation(String quotationId);
  Future<void> rejectQuotation(String quotationId);

  Future<List<RfqAttachment>> fetchAttachments(String rfqId);
  Future<void> uploadAttachment({
    required String rfqId,
    required String fileName,
    required Uint8List bytes,
  });
  Future<void> deleteAttachment(RfqAttachment attachment);
  Future<String> attachmentUrl(String storagePath);
}

class SupabaseRfqRepository implements RfqRepository {
  SupabaseRfqRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<RfqSummary>> fetchMyRfqs() async {
    final res = await _client.rpc('get_my_rfqs');
    return rpcRows(res).map(RfqSummary.fromJson).toList();
  }

  @override
  Future<ContractorStats> fetchStats() async {
    final res = await _client.rpc('get_contractor_stats');
    return ContractorStats.fromJson(rpcFirstRow(res));
  }

  @override
  Future<RfqDetail> fetchRfq(String rfqId) async {
    final row = await _client
        .from('rfqs')
        .select(
          'id, ref_no, title, description, delivery_location, required_by, status, created_at, hired_quotation_id, '
          'rfq_items(id, line_no, item_name, category_id, specification, quantity, unit)',
        )
        .eq('id', rfqId)
        .single();
    return RfqDetail.fromJson(row);
  }

  @override
  Future<String> saveRfq(RfqInput input, {required bool publish, String? rfqId}) async {
    final res = await _client.rpc('save_rfq', params: {
      'p_title': input.title,
      'p_description': input.description,
      'p_delivery_location': input.deliveryLocation,
      'p_required_by': Fmt.isoDate(input.requiredBy),
      'p_items': input.items.map((e) => e.toJson()).toList(),
      'p_publish': publish,
      'p_rfq_id': rfqId,
    });
    return res as String;
  }

  @override
  Future<void> updateStatus(String rfqId, RfqStatus status) async {
    await _client.from('rfqs').update({'status': status.dbValue}).eq('id', rfqId);
  }

  @override
  Future<void> deleteRfq(String rfqId) async {
    final deleted = await _client.from('rfqs').delete().eq('id', rfqId).select('id');
    if (deleted.isEmpty) {
      throw const AppException('This RFQ can only be deleted while it is a draft or nobody has responded.');
    }
  }

  @override
  Future<List<ContractorQuotation>> fetchQuotations(String rfqId) async {
    final res = await _client.rpc('get_rfq_quotations', params: {'p_rfq_id': rfqId});
    return rpcRows(res).map(ContractorQuotation.fromJson).toList();
  }

  @override
  Future<void> markQuotationViewed(String quotationId) async {
    await _client.rpc('mark_quotation_viewed', params: {'p_quotation_id': quotationId});
  }

  @override
  Future<QuotationStatus> setShortlisted(String quotationId, bool shortlisted) async {
    final res = await _client.rpc(
      'set_quotation_shortlisted',
      params: {'p_quotation_id': quotationId, 'p_shortlisted': shortlisted},
    );
    return QuotationStatus.fromDb(res?.toString());
  }

  @override
  Future<RevealedContact> acceptQuotation(String quotationId) async {
    final res = await _client.rpc('accept_quotation', params: {'p_quotation_id': quotationId});
    return RevealedContact.fromJson(rpcFirstRow(res));
  }

  @override
  Future<void> rejectQuotation(String quotationId) async {
    await _client.rpc('reject_quotation', params: {'p_quotation_id': quotationId});
  }

  @override
  Future<List<RfqAttachment>> fetchAttachments(String rfqId) async {
    final rows = await _client
        .from('rfq_attachments')
        .select('id, rfq_id, storage_path, file_name, size_bytes, mime_type')
        .eq('rfq_id', rfqId)
        .order('created_at');
    return rows.map(RfqAttachment.fromJson).toList();
  }

  @override
  Future<void> uploadAttachment({
    required String rfqId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    if (!AppConstants.attachmentExtensions.contains(ext)) {
      throw const AppException('Only PDF, DWG and Excel files can be attached.');
    }
    // Random object name: the original file name could reveal the company.
    final objectName = '$rfqId/${_randomToken()}${_randomToken()}.$ext';
    final mime = AppConstants.mimeForExtension(ext);

    await _client.storage
        .from(AppConstants.rfqAttachmentsBucket)
        .uploadBinary(objectName, bytes, fileOptions: FileOptions(contentType: mime));

    try {
      await _client.from('rfq_attachments').insert({
        'rfq_id': rfqId,
        'storage_path': objectName,
        'file_name': fileName,
        'size_bytes': bytes.length,
        'mime_type': mime,
      });
    } catch (_) {
      // keep storage and metadata consistent
      await _client.storage.from(AppConstants.rfqAttachmentsBucket).remove([objectName]);
      rethrow;
    }
  }

  @override
  Future<void> deleteAttachment(RfqAttachment attachment) async {
    await _client.from('rfq_attachments').delete().eq('id', attachment.id);
    await _client.storage.from(AppConstants.rfqAttachmentsBucket).remove([attachment.storagePath]);
  }

  @override
  Future<String> attachmentUrl(String storagePath) =>
      _client.storage.from(AppConstants.rfqAttachmentsBucket).createSignedUrl(storagePath, 600);

  static final _rng = Random.secure();
  static String _randomToken() => List.generate(8, (_) => _rng.nextInt(16).toRadixString(16)).join();
}
