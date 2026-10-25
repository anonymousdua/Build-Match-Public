# BuildMatch

Windows desktop app (Flutter) that connects construction **contractors** and **suppliers**.
Contractors publish RFQs, the database matches them to suppliers who stock the items, matched
suppliers reply with BOQs (quotations), and both sides stay **anonymous** until the contractor
hires a supplier.

- Flutter · MVVM · Provider · go_router
- Supabase (Postgres + Auth + Storage), all protection enforced server-side with RLS

---

## 1. Supabase setup

1. Create a project at <https://supabase.com>.
2. **Run the SQL** — either:
   - **SQL Editor:** paste `supabase/buildmatch_all_in_one.sql` and click **Run**, or
   - **CLI:** `supabase link --project-ref <ref>` then `supabase db push`
     (uses `supabase/migrations/*`).

   If your project still has the earlier prototype `profiles` table, run
   `supabase/migrations/20261025090000_reset_legacy_profiles.sql` first.
3. **Auth → Providers → Email:** keep Email enabled.
   - *Confirm email* ON (recommended): after sign-up the app shows "Confirm your email".
   - *Confirm email* OFF: users are signed in straight after sign-up.
4. **Auth → URL configuration:** set *Site URL* to a page you control. Password-reset and
   confirmation emails link there (a desktop app has no web page of its own).
5. **Project Settings → API:** copy the *Project URL* and the **anon public** key.

What the SQL creates:

| Area | Objects |
|---|---|
| Tables | `profiles`, `categories`, `rfqs`, `rfq_items`, `rfq_attachments`, `products`, `matches`, `quotations`, `quotation_items`, `reveals` |
| Matching | `private.compute_matches` / `private.refresh_matches` + triggers on RFQ publish, RFQ items and products. Same category **and** a shared keyword (case-insensitive); score = matched lines ÷ total lines |
| Anonymity | Contractors never read `quotations`/`matches` directly and suppliers never read `rfqs`/other profiles. Cross-party data comes only from `SECURITY DEFINER` RPCs that return aliases (`Contractor #C-4821`). Company name + email are returned only when a `reveals` row exists (created by `accept_quotation`) |
| RPCs used by the app | `save_rfq`, `get_my_rfqs`, `get_contractor_stats`, `get_rfq_quotations`, `mark_quotation_viewed`, `set_quotation_shortlisted`, `accept_quotation`, `reject_quotation`, `get_supplier_stats`, `get_matched_rfqs`, `get_supplier_rfq`, `submit_quotation`, `get_my_quotations` |
| Storage | Private buckets `rfq-attachments` (25 MB, PDF/DWG/XLSX) and `product-images` (5 MB, PNG/JPG) with folder-based policies |

## 2. Configure the app

```bash
cp .env.example .env      # Windows: copy .env.example .env
```

Fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY`. **Never** put the `service_role` key in this app.

> **Security note.** `.env` is bundled as an asset, and anything bundled in a desktop app can be
> extracted by the person who has the installer. The anon key is therefore treated as public.
> Data is protected by Row Level Security, column-level grants, server-side triggers and
> `SECURITY DEFINER` RPCs — not by keeping the key secret. `.env` is in `.gitignore`;
> `.env.example` is committed.

## 3. Run

Requirements: Flutter **3.29+** with Windows desktop support (Visual Studio 2022 with
"Desktop development with C++").

```bash
flutter config --enable-windows-desktop
flutter create --platforms=windows --project-name buildmatch .   # adds windows/ runner only, keeps lib/
flutter pub get
flutter run -d windows
```

Quality checks:

```bash
flutter analyze
flutter test
```

## 4. Build a release

```bash
flutter build windows --release
```

The app is in `build\windows\x64\runner\Release\` — ship the **whole folder**
(`buildmatch.exe` + DLLs + `data\`). To make an installer, wrap that folder with
Inno Setup / MSIX (`dart run msix:create` after adding the `msix` package).

## 5. Architecture

```
lib/
  core/        theme, constants (field limits), utils (InputSanitizer, ErrorMapper, Fmt), env, router
  models/      plain data classes with fromJson/toJson
  services/    repositories – the ONLY place that talks to Supabase
  viewmodels/  ChangeNotifier per screen: state, validation, loading/error
  views/       widgets only; read state from ViewModels, never call Supabase
supabase/
  migrations/  ordered SQL migrations
  buildmatch_all_in_one.sql
test/          sanitizer + ViewModel unit tests with fake repositories
```

- **Navigation / guards:** `core/router/app_router.dart`. Signed-out users only see login/sign-up;
  contractors cannot open `/supplier/*` and vice-versa (the database enforces the same rules).
- **Input handling:** every field is validated in its ViewModel through `InputSanitizer`
  (trim, strip control characters, length limits, email/number/date checks, reject script/SQL
  patterns). The database repeats the important checks with `CHECK` constraints. No SQL is ever
  built from strings — only the query builder and parameterised RPCs.
- **Errors:** `ErrorMapper` turns exceptions into short user messages; raw exceptions are never shown.
  Messages raised on purpose by the SQL functions (code `P0001`) are shown as written.

## 6. Using the app

| Contractor | Supplier |
|---|---|
| **Create RFQ** – title, location (city/region only), required-by date, line items, optional attachments. *Save draft* or *Publish RFQ*. | **Add product** – name, category, unit, price range, lead time, availability, image. Products are matched to open RFQs immediately. |
| **My RFQs** – search, filter by status, sort. | **Matched RFQs** – match %, contractor alias, *Send BOQ*. |
| **RFQ detail** – BOQ cards (best price highlighted), shortlist ★, side-by-side comparison, *Mark as hired* (reveals both identities), reject, status changes, close. | **Create BOQ** – choose your product per requested line (★ = matched), qty, unit price, availability, delivery date; *Save draft* or *Send BOQ*. |
| | **My BOQs** – status (Sent / Viewed / Shortlisted / Accepted / Rejected); contractor contact appears after acceptance. |

Keyboard: **Enter** submits the form you're in (Ctrl+Enter inside multi-line fields),
**Ctrl+K** jumps to the search bar.

Design changes vs. the mock-ups (as requested): no demo login buttons, no notification bell,
no notification settings.
