import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../models/rfq.dart';

/// Opens the RFQ detail page (drafts show Edit / Publish there).
void openRfq(BuildContext context, RfqSummary r) => context.go(Routes.contractorRfq(r.id));
