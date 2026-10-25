import 'dart:typed_data';

import '../../core/constants/app_constants.dart';
import '../../core/utils/error_mapper.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/input_sanitizer.dart';
import '../../models/category.dart';
import '../../models/enums.dart';
import '../../models/rfq.dart';
import '../../services/category_repository.dart';
import '../../services/rfq_repository.dart';
import '../base_view_model.dart';

/// Editable line item row on the Create RFQ form.
class RfqLineDraft {
  RfqLineDraft({
    required this.key,
    this.itemName = '',
    this.categoryId,
    this.specification = '',
    this.quantityText = '',
    this.unit = UnitType.bag,
  });

  final int key; // stable widget key
  String itemName;
  String? categoryId;
  String specification;
  String quantityText;
  UnitType unit;
}

/// File chosen on the form, uploaded after the RFQ is saved.
class PendingFile {
  const PendingFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

/// Create RFQ / edit draft screen.
class RfqFormViewModel extends BaseViewModel {
  RfqFormViewModel(this._rfqs, this._categories, {this.rfqId}) : _currentId = rfqId;

  final RfqRepository _rfqs;
  final CategoryRepository _categories;
  final String? rfqId;

  /// Becomes set after the first successful save so retries update the same
  /// RFQ instead of creating a duplicate draft.
  String? _currentId;

  bool get isEdit => rfqId != null;
  bool _isPublished = false;

  /// Editing an RFQ that is already open (no "Save draft" button then).
  bool get isPublished => _isPublished;

  List<Category> _categoryList = const [];
  List<Category> get categories => _categoryList;

  String title = '';
  String description = '';
  String deliveryLocation = '';
  DateTime? requiredBy;
  String? dateError;

  final List<RfqLineDraft> _lines = [];
  List<RfqLineDraft> get lines => List.unmodifiable(_lines);
  int _nextKey = 0;
  String? linesError;

  final List<PendingFile> _pendingFiles = [];
  List<PendingFile> get pendingFiles => List.unmodifiable(_pendingFiles);
  List<RfqAttachment> _existingFiles = const [];
  List<RfqAttachment> get existingFiles => _existingFiles;
  String? fileError;

  /// Set after a successful save so the view can navigate.
  String? savedRfqId;
  bool savedAsPublished = false;
  String? uploadWarning;

  Future<void> load() async {
    await runLoad(() async {
      _categoryList = await _categories.fetchAll();
      if (rfqId != null) {
        final rfq = await _rfqs.fetchRfq(rfqId!);
        if (rfq.status != RfqStatus.draft && rfq.status != RfqStatus.open) {
          throw const AppException('This RFQ can no longer be edited.');
        }
        _isPublished = rfq.status == RfqStatus.open;
        title = rfq.title;
        description = rfq.description ?? '';
        deliveryLocation = rfq.deliveryLocation;
        requiredBy = rfq.requiredBy;
        _lines
          ..clear()
          ..addAll(rfq.items.map((i) => RfqLineDraft(
                key: _nextKey++,
                itemName: i.itemName,
                categoryId: i.categoryId,
                specification: i.specification ?? '',
                quantityText: Fmt.plainNumber(i.quantity),
                unit: i.unit,
              )));
        _existingFiles = await _rfqs.fetchAttachments(rfqId!);
      }
      if (_lines.isEmpty) addLine();
    });
  }

  // ---- line items ----------------------------------------------------------
  void addLine() {
    if (_lines.length >= AppLimits.rfqItemsMax) {
      linesError = 'An RFQ can have at most ${AppLimits.rfqItemsMax} line items.';
    } else {
      _lines.add(RfqLineDraft(key: _nextKey++, categoryId: _categoryList.isEmpty ? null : _categoryList.first.id));
      linesError = null;
    }
    notifyListeners();
  }

  void removeLine(int key) {
    _lines.removeWhere((l) => l.key == key);
    notifyListeners();
  }

  void updateLine(int key, {String? itemName, String? categoryId, String? specification, String? quantityText, UnitType? unit}) {
    final l = _lines.firstWhere((e) => e.key == key);
    if (itemName != null) l.itemName = itemName;
    if (categoryId != null) l.categoryId = categoryId;
    if (specification != null) l.specification = specification;
    if (quantityText != null) l.quantityText = quantityText;
    if (unit != null) {
      l.unit = unit;
      notifyListeners(); // dropdown needs a rebuild; text fields don't
    }
    if (categoryId != null) notifyListeners();
  }

  void setRequiredBy(DateTime? date) {
    requiredBy = date;
    dateError = null;
    notifyListeners();
  }

  // ---- attachments ---------------------------------------------------------
  void addFiles(List<PendingFile> files) {
    fileError = null;
    for (final f in files) {
      final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
      if (!AppConstants.attachmentExtensions.contains(ext)) {
        fileError = '${f.name}: only PDF, DWG or XLSX files are allowed.';
        continue;
      }
      if (f.bytes.length > AppLimits.attachmentMaxBytes) {
        fileError = '${f.name} is larger than 25 MB.';
        continue;
      }
      final cleanName = InputSanitizer.clean(f.name);
      if (cleanName.isEmpty || cleanName.length > 200) {
        fileError = 'File names must be 1–200 characters.';
        continue;
      }
      _pendingFiles.add(PendingFile(name: cleanName, bytes: f.bytes));
    }
    notifyListeners();
  }

  void removePendingFile(PendingFile f) {
    _pendingFiles.remove(f);
    notifyListeners();
  }

  Future<void> removeExistingFile(RfqAttachment a) async {
    final ok = await runAction(() => _rfqs.deleteAttachment(a));
    if (ok) {
      _existingFiles = _existingFiles.where((e) => e.id != a.id).toList();
      notifyListeners();
    }
  }

  // ---- validation (used by the Form fields) --------------------------------
  String? validateTitle(String? v) => InputSanitizer.validateText(v,
      field: 'Project title', min: AppLimits.rfqTitleMin, max: AppLimits.rfqTitleMax);
  String? validateLocation(String? v) => InputSanitizer.validateText(v,
      field: 'Delivery location', min: AppLimits.locationMin, max: AppLimits.locationMax);
  String? validateDescription(String? v) => InputSanitizer.validateText(v,
      field: 'Description', required: false, max: AppLimits.rfqDescriptionMax, multiline: true);
  String? validateItemName(String? v) =>
      InputSanitizer.validateText(v, field: 'Item name', max: AppLimits.itemNameMax);
  String? validateSpecification(String? v) =>
      InputSanitizer.validateText(v, field: 'Specification', required: false, max: AppLimits.specificationMax);
  String? validateQuantity(String? v) =>
      InputSanitizer.validateNumber(v, field: 'Quantity', max: AppLimits.quantityMax);

  /// Checks the parts not covered by TextFormField validators.
  bool validateExtras({required bool publish}) {
    dateError = InputSanitizer.validateDate(requiredBy, field: 'Required-by date');
    linesError = null;
    if (publish && _lines.isEmpty) linesError = 'Add at least one line item before publishing.';
    if (_lines.any((l) => l.categoryId == null)) linesError = 'Choose a category for every line item.';
    notifyListeners();
    return dateError == null && linesError == null;
  }

  // ---- save ----------------------------------------------------------------
  /// [formValid] = result of Form.validate() in the view.
  Future<bool> save({required bool publish, required bool formValid}) async {
    final extrasOk = validateExtras(publish: publish);
    if (!formValid || !extrasOk) return false;

    final input = RfqInput(
      title: InputSanitizer.clean(title),
      description: InputSanitizer.cleanOrNull(description, multiline: true),
      deliveryLocation: InputSanitizer.clean(deliveryLocation),
      requiredBy: requiredBy!,
      items: _lines
          .map((l) => RfqItemInput(
                itemName: InputSanitizer.clean(l.itemName),
                categoryId: l.categoryId!,
                specification: InputSanitizer.cleanOrNull(l.specification),
                quantity: InputSanitizer.parseNumber(l.quantityText)!,
                unit: l.unit,
              ))
          .toList(),
    );

    uploadWarning = null;
    return runAction(() async {
      // Upload files while still editable (before publishing makes BOQs possible).
      final id = await _rfqs.saveRfq(input, publish: false, rfqId: _currentId);
      _currentId = id;
      for (final f in List<PendingFile>.from(_pendingFiles)) {
        try {
          await _rfqs.uploadAttachment(rfqId: id, fileName: f.name, bytes: f.bytes);
          _pendingFiles.remove(f);
        } catch (e) {
          uploadWarning = 'Some attachments could not be uploaded: ${ErrorMapper.message(e)}';
        }
      }
      if (publish) await _rfqs.updateStatus(id, RfqStatus.open);
      savedRfqId = id;
      savedAsPublished = publish;
    });
  }
}
