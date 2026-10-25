/// Mirrors the Postgres enums. `dbValue` is what the API sends/accepts.
enum UserRole {
  contractor('contractor', 'Contractor'),
  supplier('supplier', 'Supplier');

  const UserRole(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static UserRole fromDb(String? v) => values.firstWhere((e) => e.dbValue == v, orElse: () => contractor);
}

enum RfqStatus {
  draft('draft', 'Draft'),
  open('open', 'Open'),
  boqsReceived('boqs_received', 'BOQs Received'),
  underReview('under_review', 'Under Review'),
  hired('hired', 'Supplier Hired'),
  closed('closed', 'Not Hired / Closed');

  const RfqStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static RfqStatus fromDb(String? v) => values.firstWhere((e) => e.dbValue == v, orElse: () => draft);

  bool get isActive => this == open || this == boqsReceived || this == underReview;
  bool get isFinal => this == hired || this == closed;

  /// Statuses a contractor can pick from the status dropdown.
  /// "Hired" is reached only by accepting a BOQ.
  static const manual = [open, boqsReceived, underReview, closed];
}

enum QuotationStatus {
  draft('draft', 'Draft'),
  sent('sent', 'Sent'),
  viewed('viewed', 'Viewed'),
  shortlisted('shortlisted', 'Shortlisted'),
  accepted('accepted', 'Accepted'),
  rejected('rejected', 'Rejected');

  const QuotationStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static QuotationStatus fromDb(String? v) => values.firstWhere((e) => e.dbValue == v, orElse: () => draft);

  bool get isPending => this == sent || this == viewed || this == shortlisted;
}

enum Availability {
  inStock('in_stock', 'In stock'),
  partial('partial', 'Partial'),
  onOrder('on_order', 'On order');

  const Availability(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static Availability fromDb(String? v) => values.firstWhere((e) => e.dbValue == v, orElse: () => inStock);
}

enum UnitType {
  bag('bag', 'bag'),
  ton('ton', 'ton'),
  kg('kg', 'kg'),
  m('m', 'm'),
  m2('m2', 'm²'),
  m3('m3', 'm³'),
  pcs('pcs', 'pcs'),
  roll('roll', 'roll'),
  litre('litre', 'litre'),
  unitSet('set', 'set'),
  lot('lot', 'lot');

  const UnitType(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static UnitType fromDb(String? v) => values.firstWhere((e) => e.dbValue == v, orElse: () => pcs);
}
