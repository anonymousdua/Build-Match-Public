import 'dart:async';
import 'dart:typed_data';

import 'package:buildmatch/core/utils/error_mapper.dart';
import 'package:buildmatch/models/category.dart';
import 'package:buildmatch/models/enums.dart';
import 'package:buildmatch/models/quotation.dart';
import 'package:buildmatch/models/rfq.dart';
import 'package:buildmatch/models/user_profile.dart';
import 'package:buildmatch/services/auth_repository.dart';
import 'package:buildmatch/services/category_repository.dart';
import 'package:buildmatch/services/rfq_repository.dart';

/// In-memory fakes so ViewModels can be tested without Supabase.

class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<bool>.broadcast();
  bool signedIn = false;
  Object? signInError;
  Object? signUpError;
  SignUpOutcome signUpOutcome = SignUpOutcome.signedIn;

  String? lastEmail;
  String? lastPassword;
  String? lastCompany;
  UserRole? lastRole;
  int signInCalls = 0;
  int resetCalls = 0;

  @override
  Stream<bool> get sessionChanges => _controller.stream;
  @override
  bool get hasSession => signedIn;
  @override
  String? get currentUserId => signedIn ? 'user-1' : null;
  @override
  String? get currentEmail => lastEmail;

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    lastEmail = email;
    lastPassword = password;
    if (signInError != null) throw signInError!;
    signedIn = true;
    _controller.add(true);
  }

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String companyName,
    required UserRole role,
  }) async {
    lastEmail = email;
    lastPassword = password;
    lastCompany = companyName;
    lastRole = role;
    if (signUpError != null) throw signUpError!;
    return signUpOutcome;
  }

  @override
  Future<void> signOut() async {
    signedIn = false;
    _controller.add(false);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    resetCalls++;
    lastEmail = email;
  }

  @override
  Future<void> updateEmail(String email) async => lastEmail = email;
}

class FakeProfileRepository implements ProfileRepository {
  UserProfile profile = const UserProfile(
    id: 'user-1',
    role: UserRole.contractor,
    companyName: 'Gulf Build Contracting LLC',
    alias: 'Contractor #C-4821',
    aliasCode: 'C-4821',
    email: 'you@company.ae',
  );

  @override
  Future<UserProfile> fetchMyProfile() async => profile;

  @override
  Future<UserProfile> updateCompanyName(String companyName) async =>
      profile = profile.copyWith(companyName: companyName);
}

class FakeCategoryRepository implements CategoryRepository {
  final list = const [
    Category(id: 'cement-concrete', name: 'Cement & Concrete'),
    Category(id: 'steel-rebar', name: 'Steel & Rebar'),
    Category(id: 'plumbing', name: 'Plumbing'),
  ];

  @override
  Future<List<Category>> fetchAll() async => list;

  @override
  String nameFor(String id) => list.firstWhere((c) => c.id == id, orElse: () => Category(id: id, name: id)).name;
}

class SavedRfqCall {
  SavedRfqCall(this.input, this.publish, this.rfqId);
  final RfqInput input;
  final bool publish;
  final String? rfqId;
}

class FakeRfqRepository implements RfqRepository {
  List<RfqSummary> rfqs = [];
  ContractorStats stats = const ContractorStats();
  RfqDetail? detail;
  List<ContractorQuotation> quotations = [];
  List<RfqAttachment> attachments = [];

  final saveCalls = <SavedRfqCall>[];
  final statusCalls = <(String, RfqStatus)>[];
  final uploads = <String>[];
  Object? saveError;
  Object? uploadError;
  Object? statusError;
  int fetchCalls = 0;

  @override
  Future<List<RfqSummary>> fetchMyRfqs() async {
    fetchCalls++;
    return rfqs;
  }

  @override
  Future<ContractorStats> fetchStats() async => stats;

  @override
  Future<RfqDetail> fetchRfq(String rfqId) async {
    if (detail == null) throw const AppException('RFQ not found.');
    return detail!;
  }

  @override
  Future<String> saveRfq(RfqInput input, {required bool publish, String? rfqId}) async {
    saveCalls.add(SavedRfqCall(input, publish, rfqId));
    if (saveError != null) throw saveError!;
    return rfqId ?? 'rfq-new';
  }

  @override
  Future<void> updateStatus(String rfqId, RfqStatus status) async {
    if (statusError != null) throw statusError!;
    statusCalls.add((rfqId, status));
  }

  @override
  Future<void> deleteRfq(String rfqId) async {}

  @override
  Future<List<ContractorQuotation>> fetchQuotations(String rfqId) async => quotations;

  @override
  Future<void> markQuotationViewed(String quotationId) async {}

  @override
  Future<QuotationStatus> setShortlisted(String quotationId, bool shortlisted) async =>
      shortlisted ? QuotationStatus.shortlisted : QuotationStatus.viewed;

  @override
  Future<RevealedContact> acceptQuotation(String quotationId) async =>
      const RevealedContact(companyName: 'Emirates Steel Trading', email: 's1@steel.ae');

  @override
  Future<void> rejectQuotation(String quotationId) async {}

  @override
  Future<List<RfqAttachment>> fetchAttachments(String rfqId) async => attachments;

  @override
  Future<void> uploadAttachment({required String rfqId, required String fileName, required Uint8List bytes}) async {
    if (uploadError != null) throw uploadError!;
    uploads.add('$rfqId/$fileName');
  }

  @override
  Future<void> deleteAttachment(RfqAttachment attachment) async {}

  @override
  Future<String> attachmentUrl(String storagePath) async => 'https://example.test/$storagePath';
}

RfqSummary rfqSummary({
  required String id,
  required String code,
  required String title,
  RfqStatus status = RfqStatus.open,
  String location = 'Dubai, Al Barsha',
  DateTime? created,
  DateTime? requiredBy,
  int boqs = 0,
}) =>
    RfqSummary(
      id: id,
      code: code,
      title: title,
      deliveryLocation: location,
      requiredBy: requiredBy ?? DateTime(2030, 1, 1),
      status: status,
      createdAt: created ?? DateTime(2026, 10, 1),
      itemCount: 1,
      boqCount: boqs,
      matchedSupplierCount: 0,
    );

/// Lets stream events and microtasks run.
Future<void> flushEvents() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
