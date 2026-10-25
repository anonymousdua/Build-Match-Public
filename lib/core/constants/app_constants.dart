/// Field limits. These mirror the CHECK constraints in
/// supabase/migrations/20261025090100_schema.sql – keep them in sync.
class AppLimits {
  AppLimits._();

  static const emailMax = 254;
  static const passwordMin = 8;
  static const passwordMax = 72; // bcrypt limit used by Supabase Auth
  static const companyMin = 2;
  static const companyMax = 120;

  static const rfqTitleMin = 3;
  static const rfqTitleMax = 150;
  static const rfqDescriptionMax = 4000;
  static const locationMin = 2;
  static const locationMax = 120;
  static const itemNameMax = 150;
  static const specificationMax = 300;
  static const rfqItemsMax = 200;

  static const productNameMin = 2;
  static const productNameMax = 150;
  static const productDescriptionMax = 2000;
  static const productSpecsMax = 1000;
  static const leadTimeMax = 365;

  static const notesMax = 2000;

  static const quantityMax = 1000000000.0;
  static const priceMax = 100000000.0;

  static const attachmentMaxBytes = 25 * 1024 * 1024;
  static const imageMaxBytes = 5 * 1024 * 1024;
}

class AppConstants {
  AppConstants._();

  static const appName = 'BuildMatch';
  static const version = 'v1.0 · Desktop';
  static const currency = 'AED';

  static const rfqAttachmentsBucket = 'rfq-attachments';
  static const productImagesBucket = 'product-images';

  static const attachmentExtensions = ['pdf', 'dwg', 'xlsx', 'xls'];
  static const imageExtensions = ['png', 'jpg', 'jpeg'];

  static String mimeForExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'dwg':
        return 'image/vnd.dwg';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return 'application/octet-stream';
    }
  }
}
