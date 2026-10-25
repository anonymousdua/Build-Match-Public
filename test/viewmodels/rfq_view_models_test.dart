import 'dart:typed_data';

import 'package:buildmatch/core/utils/error_mapper.dart';
import 'package:buildmatch/models/enums.dart';
import 'package:buildmatch/models/quotation.dart';
import 'package:buildmatch/models/rfq.dart';
import 'package:buildmatch/viewmodels/contractor/my_rfqs_view_model.dart';
import 'package:buildmatch/viewmodels/contractor/rfq_detail_view_model.dart';
import 'package:buildmatch/viewmodels/contractor/rfq_form_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  group('RfqFormViewModel', () {
    late FakeRfqRepository repo;
    late RfqFormViewModel vm;

    setUp(() async {
      repo = FakeRfqRepository();
      vm = RfqFormViewModel(repo, FakeCategoryRepository());
      await vm.load();
    });

    void fillValid() {
      vm.title = '  Marina tower –  podium slab ';
      vm.description = 'Scope line 1\r\n\r\n\r\nline 2  ';
      vm.deliveryLocation = 'Dubai, JLT';
      vm.setRequiredBy(DateTime.now().add(const Duration(days: 30)));
      final key = vm.lines.first.key;
      vm.updateLine(key, itemName: ' OPC Cement 42.5N ', categoryId: 'cement-concrete', quantityText: '4,200', unit: UnitType.bag);
    }

    test('starts with one empty line and loaded categories', () {
      expect(vm.lines, hasLength(1));
      expect(vm.categories, isNotEmpty);
      expect(vm.isEdit, isFalse);
    });

    test('add / remove lines', () {
      vm.addLine();
      vm.addLine();
      expect(vm.lines, hasLength(3));
      vm.removeLine(vm.lines[1].key);
      expect(vm.lines, hasLength(2));
    });

    test('field validators', () {
      expect(vm.validateTitle('ab'), isNotNull);
      expect(vm.validateTitle('Marina tower – podium slab'), isNull);
      expect(vm.validateLocation(''), isNotNull);
      expect(vm.validateQuantity('0'), isNotNull);
      expect(vm.validateQuantity('12.5'), isNull);
      expect(vm.validateItemName("Rebar'; DROP TABLE rfqs; --"), contains('not allowed'));
      expect(vm.validateDescription(''), isNull);
    });

    test('does not save when the form is invalid', () async {
      fillValid();
      final ok = await vm.save(publish: true, formValid: false);
      expect(ok, isFalse);
      expect(repo.saveCalls, isEmpty);
    });

    test('requires a required-by date', () async {
      fillValid();
      vm.setRequiredBy(null);
      final ok = await vm.save(publish: false, formValid: true);
      expect(ok, isFalse);
      expect(vm.dateError, isNotNull);
      expect(repo.saveCalls, isEmpty);
    });

    test('publishing needs at least one line', () async {
      fillValid();
      vm.removeLine(vm.lines.first.key);
      final ok = await vm.save(publish: true, formValid: true);
      expect(ok, isFalse);
      expect(vm.linesError, isNotNull);
    });

    test('saves cleaned values, uploads files, then publishes', () async {
      fillValid();
      vm.addFiles([PendingFile(name: 'drawing.pdf', bytes: Uint8List.fromList([1, 2, 3]))]);
      final ok = await vm.save(publish: true, formValid: true);

      expect(ok, isTrue);
      expect(repo.saveCalls, hasLength(1));
      final input = repo.saveCalls.single.input;
      expect(input.title, 'Marina tower – podium slab');
      expect(input.description, 'Scope line 1\n\nline 2');
      expect(input.items.single.itemName, 'OPC Cement 42.5N');
      expect(input.items.single.quantity, 4200);
      expect(input.items.single.unit, UnitType.bag);
      // saved as a draft first so attachments upload before suppliers can respond
      expect(repo.saveCalls.single.publish, isFalse);
      expect(repo.uploads, ['rfq-new/drawing.pdf']);
      expect(repo.statusCalls, [('rfq-new', RfqStatus.open)]);
      expect(vm.savedRfqId, 'rfq-new');
      expect(vm.pendingFiles, isEmpty);
    });

    test('a retry after a failure updates the same RFQ instead of creating a duplicate', () async {
      fillValid();
      repo.statusError = const AppException('Network down');
      expect(await vm.save(publish: true, formValid: true), isFalse); // saved as draft, publish failed
      expect(repo.saveCalls.last.rfqId, isNull);

      repo.statusError = null;
      expect(await vm.save(publish: true, formValid: true), isTrue);
      expect(repo.saveCalls.last.rfqId, 'rfq-new'); // same RFQ, no duplicate draft
    });

    test('server errors are shown as friendly text', () async {
      fillValid();
      repo.saveError = const AppException('This RFQ can no longer be edited.');
      final ok = await vm.save(publish: false, formValid: true);
      expect(ok, isFalse);
      expect(vm.actionError, 'This RFQ can no longer be edited.');
    });

    test('rejects disallowed or oversized attachments', () {
      vm.addFiles([PendingFile(name: 'virus.exe', bytes: Uint8List(10))]);
      expect(vm.pendingFiles, isEmpty);
      expect(vm.fileError, contains('only PDF'));

      vm.addFiles([PendingFile(name: 'big.pdf', bytes: Uint8List(26 * 1024 * 1024))]);
      expect(vm.pendingFiles, isEmpty);
      expect(vm.fileError, contains('25 MB'));

      vm.addFiles([PendingFile(name: 'plan.dwg', bytes: Uint8List(10))]);
      expect(vm.pendingFiles, hasLength(1));
    });

    test('edit mode loads the existing RFQ', () async {
      repo.detail = RfqDetail(
        id: 'rfq-1',
        refNo: 2041,
        title: 'Al Barsha tower',
        deliveryLocation: 'Dubai, Al Barsha',
        requiredBy: DateTime(2030, 1, 1),
        status: RfqStatus.draft,
        createdAt: DateTime(2026, 10, 2),
        items: const [
          RfqItem(id: 'i1', lineNo: 1, itemName: 'Rebar 16mm', categoryId: 'steel-rebar', quantity: 85, unit: UnitType.ton),
        ],
      );
      final edit = RfqFormViewModel(repo, FakeCategoryRepository(), rfqId: 'rfq-1');
      await edit.load();
      expect(edit.title, 'Al Barsha tower');
      expect(edit.lines.single.itemName, 'Rebar 16mm');
      expect(edit.lines.single.quantityText, '85');
      expect(edit.isPublished, isFalse);
    });

    test('edit mode refuses finalised RFQs', () async {
      repo.detail = RfqDetail(
        id: 'rfq-1',
        refNo: 2041,
        title: 'Done',
        deliveryLocation: 'Dubai',
        requiredBy: DateTime(2030, 1, 1),
        status: RfqStatus.hired,
        createdAt: DateTime(2026, 10, 2),
        items: const [],
      );
      final edit = RfqFormViewModel(repo, FakeCategoryRepository(), rfqId: 'rfq-1');
      await edit.load();
      expect(edit.loadError, 'This RFQ can no longer be edited.');
    });
  });

  group('MyRfqsViewModel', () {
    late FakeRfqRepository repo;

    setUp(() {
      repo = FakeRfqRepository()
        ..rfqs = [
          rfqSummary(id: '1', code: 'RFQ-2047', title: 'Ajman school extension – plumbing', location: 'Ajman, Al Jurf', created: DateTime(2026, 10, 18)),
          rfqSummary(id: '2', code: 'RFQ-2041', title: 'Al Barsha residential tower', status: RfqStatus.boqsReceived, created: DateTime(2026, 10, 2), boqs: 4),
          rfqSummary(id: '3', code: 'RFQ-2035', title: 'Abu Dhabi villa cluster', status: RfqStatus.hired, location: 'Abu Dhabi', created: DateTime(2026, 9, 21)),
        ];
    });

    test('loads and sorts newest first by default', () async {
      final vm = MyRfqsViewModel(repo);
      await vm.load();
      expect(vm.visible.map((r) => r.code), ['RFQ-2047', 'RFQ-2041', 'RFQ-2035']);
    });

    test('search matches title, code and location (case-insensitive)', () async {
      final vm = MyRfqsViewModel(repo);
      await vm.load();
      vm.setQuery('  ajman ');
      expect(vm.visible.single.id, '1');
      vm.setQuery('rfq-2041');
      expect(vm.visible.single.id, '2');
      vm.setQuery('abu dhabi');
      expect(vm.visible.single.id, '3');
    });

    test('initial query from the global search bar', () async {
      final vm = MyRfqsViewModel(repo, initialQuery: 'barsha');
      await vm.load();
      expect(vm.visible.single.id, '2');
    });

    test('status filter', () async {
      final vm = MyRfqsViewModel(repo);
      await vm.load();
      vm.setStatusFilter(RfqStatus.hired);
      expect(vm.visible.single.id, '3');
      vm.setStatusFilter(null);
      expect(vm.visible, hasLength(3));
    });

    test('sorting toggles direction', () async {
      final vm = MyRfqsViewModel(repo);
      await vm.load();
      vm.sortBy(RfqSortField.title);
      expect(vm.visible.first.id, '3'); // ascending: Abu Dhabi first
      vm.sortBy(RfqSortField.title);
      expect(vm.visible.first.id, '2'); // descending: Al Barsha > Ajman > Abu Dhabi
    });

    test('load error is friendly', () async {
      final vm = MyRfqsViewModel(_ThrowingRepo());
      await vm.load();
      expect(vm.loadError, isNotNull);
      expect(vm.isLoading, isFalse);
    });
  });

  group('RfqDetailViewModel', () {
    ContractorQuotation q(String id, double total, Map<String, double> prices, {QuotationStatus status = QuotationStatus.sent}) =>
        ContractorQuotation(
          id: id,
          code: 'BOQ-2041-$id',
          supplierAlias: 'Supplier #S-$id',
          status: status,
          totalAmount: total,
          coveredItems: prices.length,
          totalItems: 2,
          isRevealed: false,
          lines: [for (final e in prices.entries) QuotationLine(rfqItemId: e.key, unitPrice: e.value, quantity: 1, lineTotal: e.value)],
        );

    late FakeRfqRepository repo;
    late RfqDetailViewModel vm;

    setUp(() async {
      repo = FakeRfqRepository()
        ..detail = RfqDetail(
          id: 'rfq-1',
          refNo: 2041,
          title: 'Al Barsha tower',
          deliveryLocation: 'Dubai',
          requiredBy: DateTime(2030, 1, 1),
          status: RfqStatus.boqsReceived,
          createdAt: DateTime(2026, 10, 2),
          items: const [
            RfqItem(id: 'cement', lineNo: 1, itemName: 'OPC Cement', categoryId: 'cement-concrete', quantity: 10, unit: UnitType.bag),
            RfqItem(id: 'rebar', lineNo: 2, itemName: 'Rebar', categoryId: 'steel-rebar', quantity: 1, unit: UnitType.ton),
          ],
        )
        ..quotations = [
          q('1093', 678756.4, {'cement': 18, 'rebar': 2544}),
          q('2271', 619549.3, {'cement': 17.46, 'rebar': 2703}),
          q('4410', 397769.9, {'cement': 18.18}),
        ];
      vm = RfqDetailViewModel(repo, FakeCategoryRepository(), 'rfq-1');
      await vm.load();
    });

    test('best total and lowest price per line', () {
      expect(vm.bestPriceId, '4410');
      expect(vm.lowestPriceFor('cement'), '2271');
      expect(vm.lowestPriceFor('rebar'), '1093');
      expect(vm.categoryName('steel-rebar'), 'Steel & Rebar');
    });

    test('rejected BOQs are ignored for best price', () async {
      await vm.reject(vm.quotations.firstWhere((e) => e.id == '4410'));
      expect(vm.bestPriceId, '2271');
    });

    test('shortlist toggles status locally', () async {
      final target = vm.quotations.first;
      await vm.toggleShortlist(target);
      expect(vm.quotations.first.status, QuotationStatus.shortlisted);
    });

    test('accept stores the revealed contact and reloads', () async {
      final ok = await vm.accept(vm.quotations.first);
      expect(ok, isTrue);
      expect(vm.lastRevealed?.companyName, 'Emirates Steel Trading');
    });

    test('RFQ with BOQs cannot be edited or deleted', () {
      expect(vm.canEdit, isFalse);
      expect(vm.canDelete, isFalse);
      expect(vm.canDecide, isTrue);
    });
  });
}

class _ThrowingRepo extends FakeRfqRepository {
  @override
  Future<List<RfqSummary>> fetchMyRfqs() async => throw StateError('db down');
}
