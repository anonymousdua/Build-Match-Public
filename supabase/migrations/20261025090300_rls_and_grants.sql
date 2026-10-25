-- =============================================================================
-- BuildMatch · 03 · Row Level Security + privileges
--
-- Two layers:
--   1. Column-level GRANTs decide WHICH columns the app may write
--      (e.g. nobody can set contractor_id / supplier_id / status internals).
--   2. RLS policies decide WHICH rows.
--
-- Anonymity by design:
--   * Contractors have NO direct read access to quotations, quotation_items or
--     matches (those rows carry supplier ids). They read BOQs only through
--     SECURITY DEFINER RPCs that return aliases (migration 04).
--   * Suppliers have NO direct read access to rfqs (carries contractor_id) or
--     to other users' profiles. They read matched RFQs only through RPCs.
--   * rfq_items / rfq_attachments carry no user ids, so matched suppliers may
--     read them directly.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Start from zero for the app roles
-- -----------------------------------------------------------------------------
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

alter table public.categories      enable row level security;
alter table public.profiles        enable row level security;
alter table public.rfqs            enable row level security;
alter table public.rfq_items       enable row level security;
alter table public.rfq_attachments enable row level security;
alter table public.products        enable row level security;
alter table public.matches         enable row level security;
alter table public.quotations      enable row level security;
alter table public.quotation_items enable row level security;
alter table public.reveals         enable row level security;

-- -----------------------------------------------------------------------------
-- categories: read-only reference data
-- -----------------------------------------------------------------------------
grant select on public.categories to authenticated;

create policy "categories: read for signed-in users"
  on public.categories for select to authenticated
  using (true);

-- -----------------------------------------------------------------------------
-- profiles: only your own row. Only company_name is editable (Settings page).
-- -----------------------------------------------------------------------------
grant select on public.profiles to authenticated;
grant update (company_name) on public.profiles to authenticated;

create policy "profiles: read own"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()));

create policy "profiles: update own"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- -----------------------------------------------------------------------------
-- rfqs: contractors manage their own
-- -----------------------------------------------------------------------------
grant select on public.rfqs to authenticated;
grant insert (title, description, delivery_location, required_by, status) on public.rfqs to authenticated;
grant update (title, description, delivery_location, required_by, status) on public.rfqs to authenticated;
grant delete on public.rfqs to authenticated;

create policy "rfqs: contractor reads own"
  on public.rfqs for select to authenticated
  using (contractor_id = (select auth.uid()));

create policy "rfqs: contractor creates own"
  on public.rfqs for insert to authenticated
  with check (contractor_id = (select auth.uid())
              and (select private.current_user_role()) = 'contractor');

create policy "rfqs: contractor updates own"
  on public.rfqs for update to authenticated
  using (contractor_id = (select auth.uid()))
  with check (contractor_id = (select auth.uid()));

-- drafts, or open RFQs nobody has answered yet
create policy "rfqs: contractor deletes own unanswered"
  on public.rfqs for delete to authenticated
  using (contractor_id = (select auth.uid())
         and status in ('draft', 'open')
         and not private.rfq_has_submitted_quotations(id));

-- -----------------------------------------------------------------------------
-- rfq_items: owner manages while editable; matched suppliers read
-- -----------------------------------------------------------------------------
grant select on public.rfq_items to authenticated;
grant insert (rfq_id, line_no, item_name, category_id, specification, quantity, unit) on public.rfq_items to authenticated;
grant update (line_no, item_name, category_id, specification, quantity, unit) on public.rfq_items to authenticated;
grant delete on public.rfq_items to authenticated;

create policy "rfq_items: owner or matched supplier reads"
  on public.rfq_items for select to authenticated
  using (private.is_rfq_owner(rfq_id) or private.is_matched_supplier(rfq_id));

create policy "rfq_items: owner inserts while editable"
  on public.rfq_items for insert to authenticated
  with check (private.is_rfq_owner(rfq_id) and private.rfq_is_editable(rfq_id));

create policy "rfq_items: owner updates while editable"
  on public.rfq_items for update to authenticated
  using (private.is_rfq_owner(rfq_id) and private.rfq_is_editable(rfq_id))
  with check (private.is_rfq_owner(rfq_id) and private.rfq_is_editable(rfq_id));

create policy "rfq_items: owner deletes while editable"
  on public.rfq_items for delete to authenticated
  using (private.is_rfq_owner(rfq_id) and private.rfq_is_editable(rfq_id));

-- -----------------------------------------------------------------------------
-- rfq_attachments: same rules as items
-- -----------------------------------------------------------------------------
grant select on public.rfq_attachments to authenticated;
grant insert (rfq_id, storage_path, file_name, size_bytes, mime_type) on public.rfq_attachments to authenticated;
grant delete on public.rfq_attachments to authenticated;

create policy "rfq_attachments: owner or matched supplier reads"
  on public.rfq_attachments for select to authenticated
  using (private.is_rfq_owner(rfq_id) or private.is_matched_supplier(rfq_id));

create policy "rfq_attachments: owner inserts while editable"
  on public.rfq_attachments for insert to authenticated
  with check (private.is_rfq_owner(rfq_id) and private.rfq_is_editable(rfq_id));

create policy "rfq_attachments: owner deletes while editable"
  on public.rfq_attachments for delete to authenticated
  using (private.is_rfq_owner(rfq_id) and private.rfq_is_editable(rfq_id));

-- -----------------------------------------------------------------------------
-- products: suppliers manage their own catalogue (nobody else can read it)
-- -----------------------------------------------------------------------------
grant select on public.products to authenticated;
grant insert (name, category_id, description, specifications, unit, available_quantity,
              price_min, price_max, lead_time_days, is_active, image_path) on public.products to authenticated;
grant update (name, category_id, description, specifications, unit, available_quantity,
              price_min, price_max, lead_time_days, is_active, image_path) on public.products to authenticated;
grant delete on public.products to authenticated;

create policy "products: supplier reads own"
  on public.products for select to authenticated
  using (supplier_id = (select auth.uid()));

create policy "products: supplier creates own"
  on public.products for insert to authenticated
  with check (supplier_id = (select auth.uid())
              and (select private.current_user_role()) = 'supplier');

create policy "products: supplier updates own"
  on public.products for update to authenticated
  using (supplier_id = (select auth.uid()))
  with check (supplier_id = (select auth.uid()));

create policy "products: supplier deletes own"
  on public.products for delete to authenticated
  using (supplier_id = (select auth.uid()));

-- -----------------------------------------------------------------------------
-- matches: suppliers see their own; written only by the matching engine
-- -----------------------------------------------------------------------------
grant select on public.matches to authenticated;

create policy "matches: supplier reads own"
  on public.matches for select to authenticated
  using (supplier_id = (select auth.uid()));

-- -----------------------------------------------------------------------------
-- quotations: suppliers manage their own; contractors use RPCs only
-- -----------------------------------------------------------------------------
grant select on public.quotations to authenticated;
grant insert (rfq_id, delivery_date, valid_until, notes, status) on public.quotations to authenticated;
grant update (delivery_date, valid_until, notes, status) on public.quotations to authenticated;
grant delete on public.quotations to authenticated;

create policy "quotations: supplier reads own"
  on public.quotations for select to authenticated
  using (supplier_id = (select auth.uid()));

create policy "quotations: matched supplier creates own"
  on public.quotations for insert to authenticated
  with check (supplier_id = (select auth.uid())
              and (select private.current_user_role()) = 'supplier'
              and private.is_matched_supplier(rfq_id));

create policy "quotations: supplier updates own draft"
  on public.quotations for update to authenticated
  using (supplier_id = (select auth.uid()) and status = 'draft')
  with check (supplier_id = (select auth.uid()));

create policy "quotations: supplier deletes own draft"
  on public.quotations for delete to authenticated
  using (supplier_id = (select auth.uid()) and status = 'draft');

-- -----------------------------------------------------------------------------
-- quotation_items: supplier reads own; edits only while the BOQ is a draft
-- -----------------------------------------------------------------------------
grant select on public.quotation_items to authenticated;
grant insert (quotation_id, rfq_item_id, product_id, quantity, unit_price, availability, delivery_date)
  on public.quotation_items to authenticated;
grant update (product_id, quantity, unit_price, availability, delivery_date)
  on public.quotation_items to authenticated;
grant delete on public.quotation_items to authenticated;

create policy "quotation_items: supplier reads own"
  on public.quotation_items for select to authenticated
  using (private.owns_quotation(quotation_id));

create policy "quotation_items: supplier inserts into own draft"
  on public.quotation_items for insert to authenticated
  with check (private.owns_draft_quotation(quotation_id));

create policy "quotation_items: supplier updates own draft"
  on public.quotation_items for update to authenticated
  using (private.owns_draft_quotation(quotation_id))
  with check (private.owns_draft_quotation(quotation_id));

create policy "quotation_items: supplier deletes from own draft"
  on public.quotation_items for delete to authenticated
  using (private.owns_draft_quotation(quotation_id));

-- -----------------------------------------------------------------------------
-- reveals: both parties of an accepted BOQ can see the reveal record
-- -----------------------------------------------------------------------------
grant select on public.reveals to authenticated;

create policy "reveals: parties read"
  on public.reveals for select to authenticated
  using (contractor_id = (select auth.uid()) or supplier_id = (select auth.uid()));
