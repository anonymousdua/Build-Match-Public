-- =============================================================================
-- BuildMatch · 02 · Internal functions & triggers
--   signup profile + alias · RLS helpers · matching engine · lifecycle rules
--
-- Conventions
--   * Every function pins `search_path = ''` and fully qualifies objects.
--   * No dynamic SQL anywhere: all values flow through parameters / NEW / OLD.
--   * "guard" triggers are SECURITY INVOKER and only police direct writes made
--     by the app role (`authenticated`). Internal work done inside SECURITY
--     DEFINER functions runs as the owner and skips the guard.
--   * "lifecycle" triggers are SECURITY DEFINER and always run.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Generic updated_at
-- -----------------------------------------------------------------------------
create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_set_updated_at   before update on public.profiles   for each row execute function private.set_updated_at();
create trigger rfqs_set_updated_at       before update on public.rfqs       for each row execute function private.set_updated_at();
create trigger products_set_updated_at   before update on public.products   for each row execute function private.set_updated_at();
create trigger matches_set_updated_at    before update on public.matches    for each row execute function private.set_updated_at();
create trigger quotations_set_updated_at before update on public.quotations for each row execute function private.set_updated_at();

-- -----------------------------------------------------------------------------
-- Alias generation:  C-4821 / S-1093  (falls back to 6 digits if 4 run out)
-- -----------------------------------------------------------------------------
create or replace function private.generate_alias_code(p_role public.user_role)
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_prefix text := case p_role when 'contractor' then 'C' else 'S' end;
  v_digits int  := 4;
  v_code   text;
  v_try    int  := 0;
begin
  loop
    v_try := v_try + 1;
    if v_try > 30 then v_digits := 6; end if;
    if v_try > 200 then
      raise exception 'Could not generate a unique alias. Please try again.';
    end if;

    v_code := v_prefix || '-' ||
              (pg_catalog.power(10, v_digits - 1)::bigint
               + pg_catalog.floor(pg_catalog.random() * 9 * pg_catalog.power(10, v_digits - 1))::bigint)::text;

    exit when not exists (select 1 from public.profiles where alias_code = v_code);
  end loop;
  return v_code;
end;
$$;

-- -----------------------------------------------------------------------------
-- Profile row on sign-up.
-- The app passes `data: {'role': 'contractor'|'supplier', 'company_name': ...}`
-- to supabase.auth.signUp().
-- -----------------------------------------------------------------------------
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role_text text := pg_catalog.lower(pg_catalog.btrim(coalesce(new.raw_user_meta_data ->> 'role', '')));
  v_role      public.user_role;
  v_company   text;
begin
  if v_role_text not in ('contractor', 'supplier') then
    raise exception 'Please choose Contractor or Supplier.';
  end if;
  v_role := v_role_text::public.user_role;

  -- strip control characters, collapse whitespace, trim
  v_company := pg_catalog.regexp_replace(coalesce(new.raw_user_meta_data ->> 'company_name', ''), '[[:cntrl:]]', '', 'g');
  v_company := pg_catalog.btrim(pg_catalog.regexp_replace(v_company, '\s+', ' ', 'g'));

  if pg_catalog.char_length(v_company) not between 2 and 120 then
    raise exception 'Company name must be between 2 and 120 characters.';
  end if;

  insert into public.profiles (id, role, company_name, email, alias_code)
  values (new.id, v_role, v_company, new.email, private.generate_alias_code(v_role));

  return new;
end;
$$;

drop trigger if exists bm_on_auth_user_created on auth.users;
create trigger bm_on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Keep profiles.email in sync when the user changes their email in Auth.
create or replace function private.sync_profile_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles set email = new.email where id = new.id;
  return new;
end;
$$;

drop trigger if exists bm_on_auth_user_email_changed on auth.users;
create trigger bm_on_auth_user_email_changed
  after update of email on auth.users
  for each row
  when (old.email is distinct from new.email)
  execute function private.sync_profile_email();

-- -----------------------------------------------------------------------------
-- RLS helpers. SECURITY DEFINER so policies can look across tables without
-- recursive RLS and without exposing the rows they look at.
-- -----------------------------------------------------------------------------
create or replace function private.current_user_role()
returns public.user_role
language sql stable security definer set search_path = ''
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function private.is_rfq_owner(p_rfq_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.rfqs where id = p_rfq_id and contractor_id = auth.uid());
$$;

create or replace function private.is_matched_supplier(p_rfq_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.matches where rfq_id = p_rfq_id and supplier_id = auth.uid());
$$;

create or replace function private.rfq_has_submitted_quotations(p_rfq_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.quotations where rfq_id = p_rfq_id and status <> 'draft');
$$;

-- RFQ details, items and attachments can change only while draft/open and
-- before any supplier has sent a BOQ against them.
create or replace function private.rfq_is_editable(p_rfq_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.rfqs r
    where r.id = p_rfq_id
      and r.status in ('draft', 'open')
      and not private.rfq_has_submitted_quotations(r.id)
  );
$$;

create or replace function private.owns_quotation(p_quotation_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.quotations where id = p_quotation_id and supplier_id = auth.uid());
$$;

create or replace function private.owns_draft_quotation(p_quotation_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.quotations
    where id = p_quotation_id and supplier_id = auth.uid() and status = 'draft'
  );
$$;

-- Safe text -> uuid for storage paths ('<uuid>/<file>'); NULL instead of an error.
create or replace function private.try_uuid(p_value text)
returns uuid
language plpgsql immutable set search_path = ''
as $$
begin
  return p_value::uuid;
exception when others then
  return null;
end;
$$;

grant execute on function
  private.current_user_role(),
  private.is_rfq_owner(uuid),
  private.is_matched_supplier(uuid),
  private.rfq_has_submitted_quotations(uuid),
  private.rfq_is_editable(uuid),
  private.owns_quotation(uuid),
  private.owns_draft_quotation(uuid),
  private.try_uuid(text)
to authenticated;

-- -----------------------------------------------------------------------------
-- MATCHING ENGINE
-- An RFQ line item matches a supplier when the supplier has an ACTIVE product
-- in the SAME category whose name shares at least one keyword with the item
-- name (case-insensitive, see private.search_tokens). If an item name has no
-- usable keywords, an exact case-insensitive name match is used instead.
-- Only RFQs in open / boqs_received / under_review are matched.
-- score = matched line items / total line items * 100
-- -----------------------------------------------------------------------------
create or replace function private.compute_matches(p_rfq_id uuid default null, p_supplier_id uuid default null)
returns table (rfq_id uuid, supplier_id uuid, matched_items integer, total_items integer)
language sql stable security definer set search_path = ''
as $$
  with active_items as (
    select i.id, i.rfq_id, i.item_name, i.category_id, i.search_tokens, r.contractor_id
    from public.rfq_items i
    join public.rfqs r on r.id = i.rfq_id
    where r.status in ('open', 'boqs_received', 'under_review')
      and (p_rfq_id is null or i.rfq_id = p_rfq_id)
  ),
  totals as (
    select ai.rfq_id, count(*)::int as n
    from active_items ai
    group by ai.rfq_id
  ),
  hits as (
    select ai.rfq_id, p.supplier_id, count(distinct ai.id)::int as matched
    from active_items ai
    join public.products p
      on p.category_id = ai.category_id
     and p.is_active
     and (
          p.search_tokens && ai.search_tokens
          or (pg_catalog.cardinality(ai.search_tokens) = 0
              and pg_catalog.lower(p.name) = pg_catalog.lower(ai.item_name))
         )
    where p.supplier_id <> ai.contractor_id
      and (p_supplier_id is null or p.supplier_id = p_supplier_id)
    group by ai.rfq_id, p.supplier_id
  )
  select h.rfq_id, h.supplier_id, h.matched, t.n
  from hits h
  join totals t on t.rfq_id = h.rfq_id;
$$;

-- Upserts matches for the given scope and removes stale ones.
-- A supplier who has already started a BOQ for an RFQ keeps the match.
create or replace function private.refresh_matches(p_rfq_id uuid default null, p_supplier_id uuid default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.matches as m (rfq_id, supplier_id, matched_items, total_items, score)
  select c.rfq_id, c.supplier_id, c.matched_items, c.total_items,
         round(100.0 * c.matched_items / greatest(c.total_items, 1), 2)
  from private.compute_matches(p_rfq_id, p_supplier_id) c
  on conflict (rfq_id, supplier_id) do update
    set matched_items = excluded.matched_items,
        total_items   = excluded.total_items,
        score         = excluded.score
    where (m.matched_items, m.total_items) is distinct from (excluded.matched_items, excluded.total_items);

  delete from public.matches m
  using public.rfqs r
  where r.id = m.rfq_id
    and r.status in ('open', 'boqs_received', 'under_review')
    and (p_rfq_id is null or m.rfq_id = p_rfq_id)
    and (p_supplier_id is null or m.supplier_id = p_supplier_id)
    and not exists (select 1 from private.compute_matches(m.rfq_id, m.supplier_id))
    and not exists (select 1 from public.quotations q
                    where q.rfq_id = m.rfq_id and q.supplier_id = m.supplier_id);
end;
$$;

-- RFQ line items changed -> re-match those RFQs (statement-level, once per RFQ)
create or replace function private.on_rfq_items_changed()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_rfq uuid;
begin
  if tg_op = 'DELETE' then
    for v_rfq in select distinct o.rfq_id from old_rows o loop
      perform private.refresh_matches(v_rfq, null);
    end loop;
  else
    for v_rfq in select distinct n.rfq_id from new_rows n loop
      perform private.refresh_matches(v_rfq, null);
    end loop;
  end if;
  return null;
end;
$$;

create trigger rfq_items_match_after_insert
  after insert on public.rfq_items referencing new table as new_rows
  for each statement execute function private.on_rfq_items_changed();
create trigger rfq_items_match_after_update
  after update on public.rfq_items referencing new table as new_rows
  for each statement execute function private.on_rfq_items_changed();
create trigger rfq_items_match_after_delete
  after delete on public.rfq_items referencing old table as old_rows
  for each statement execute function private.on_rfq_items_changed();

-- Supplier catalogue changed -> re-match that supplier against active RFQs
create or replace function private.on_products_changed()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_supplier uuid;
begin
  if tg_op = 'DELETE' then
    for v_supplier in select distinct o.supplier_id from old_rows o loop
      perform private.refresh_matches(null, v_supplier);
    end loop;
  else
    for v_supplier in select distinct n.supplier_id from new_rows n loop
      perform private.refresh_matches(null, v_supplier);
    end loop;
  end if;
  return null;
end;
$$;

create trigger products_match_after_insert
  after insert on public.products referencing new table as new_rows
  for each statement execute function private.on_products_changed();
create trigger products_match_after_update
  after update on public.products referencing new table as new_rows
  for each statement execute function private.on_products_changed();
create trigger products_match_after_delete
  after delete on public.products referencing old table as old_rows
  for each statement execute function private.on_products_changed();

-- -----------------------------------------------------------------------------
-- RFQ rules
-- -----------------------------------------------------------------------------

-- GUARD (direct writes from the app)
create or replace function private.rfqs_guard()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;   -- internal / definer context
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'draft' then
      raise exception 'New RFQs start as drafts. Publish the draft to open it.';
    end if;
    return new;
  end if;

  if new.status is distinct from old.status then
    if old.status in ('hired', 'closed') then
      raise exception 'This RFQ is already finalised and its status cannot change.';
    end if;
    if new.status = 'draft' then
      raise exception 'A published RFQ cannot be moved back to draft.';
    end if;
    if old.status = 'draft' and new.status not in ('open', 'closed') then
      raise exception 'Publish the draft first.';
    end if;
    if new.status = 'hired' then
      raise exception 'Accept a BOQ to mark a supplier as hired.';
    end if;
  end if;

  if (new.title, new.description, new.delivery_location, new.required_by)
       is distinct from (old.title, old.description, old.delivery_location, old.required_by)
     and not private.rfq_is_editable(old.id) then
    raise exception 'This RFQ can no longer be edited because suppliers have already responded.';
  end if;

  return new;
end;
$$;

create trigger rfqs_guard_before_write
  before insert or update on public.rfqs
  for each row execute function private.rfqs_guard();

-- LIFECYCLE (always)
create or replace function private.rfqs_lifecycle()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.required_by is distinct from old.required_by then
    if new.required_by < current_date then
      raise exception 'The required-by date cannot be in the past.';
    end if;
  end if;

  if new.status in ('open', 'boqs_received', 'under_review') and (tg_op = 'INSERT' or old.status = 'draft') then
    if not exists (select 1 from public.rfq_items where rfq_id = new.id) then
      raise exception 'Add at least one line item before publishing the RFQ.';
    end if;
    new.published_at := coalesce(new.published_at, now());
  end if;

  if new.status = 'hired' and (tg_op = 'INSERT' or old.status <> 'hired') then
    if new.hired_quotation_id is null or not exists (
         select 1 from public.quotations q
         where q.id = new.hired_quotation_id and q.rfq_id = new.id and q.status = 'accepted') then
      raise exception 'Accept a BOQ to mark a supplier as hired.';
    end if;
  end if;

  return new;
end;
$$;

create trigger rfqs_lifecycle_before_write
  before insert or update on public.rfqs
  for each row execute function private.rfqs_lifecycle();

create or replace function private.rfqs_after_status_change()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  -- newly published / re-activated -> run matching
  if new.status in ('open', 'boqs_received', 'under_review')
     and old.status not in ('open', 'boqs_received', 'under_review') then
    perform private.refresh_matches(new.id, null);
  end if;

  -- closed without hiring -> outstanding BOQs are rejected
  if new.status = 'closed' then
    update public.quotations
       set status = 'rejected', decided_at = now()
     where rfq_id = new.id
       and status in ('sent', 'viewed', 'shortlisted');
  end if;

  return null;
end;
$$;

create trigger rfqs_after_status_change
  after update of status on public.rfqs
  for each row
  when (old.status is distinct from new.status)
  execute function private.rfqs_after_status_change();

-- RFQ items: auto line numbers
create or replace function private.rfq_items_before_insert()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.line_no is null then
    select coalesce(max(line_no), 0) + 1 into new.line_no
    from public.rfq_items where rfq_id = new.rfq_id;
  end if;
  return new;
end;
$$;

create trigger rfq_items_before_insert
  before insert on public.rfq_items
  for each row execute function private.rfq_items_before_insert();

-- -----------------------------------------------------------------------------
-- Quotation rules
-- -----------------------------------------------------------------------------

-- GUARD (direct writes from the app = the supplier)
create or replace function private.quotations_guard()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'draft' then
      raise exception 'Save the BOQ as a draft first, then send it.';
    end if;
    return new;
  end if;

  if old.status <> 'draft' then
    raise exception 'This BOQ has already been sent and can no longer be changed.';
  end if;
  if new.status not in ('draft', 'sent') then
    raise exception 'Suppliers can only save or send a BOQ.';
  end if;
  return new;
end;
$$;

create trigger quotations_guard_before_write
  before insert or update on public.quotations
  for each row execute function private.quotations_guard();

-- LIFECYCLE (always)
create or replace function private.quotations_lifecycle()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_rfq_status public.rfq_status;
begin
  if tg_op = 'INSERT' then
    -- lock the RFQ row so ref_seq is assigned without races
    select status into v_rfq_status from public.rfqs where id = new.rfq_id for update;

    if not exists (select 1 from public.profiles where id = new.supplier_id and role = 'supplier') then
      raise exception 'Only suppliers can send BOQs.';
    end if;
    if not exists (select 1 from public.matches where rfq_id = new.rfq_id and supplier_id = new.supplier_id) then
      raise exception 'You are not matched to this RFQ.';
    end if;
    if v_rfq_status not in ('open', 'boqs_received', 'under_review') then
      raise exception 'This RFQ is no longer accepting BOQs.';
    end if;

    select coalesce(max(ref_seq), 0) + 1 into new.ref_seq
    from public.quotations where rfq_id = new.rfq_id;
  else
    new.ref_seq := old.ref_seq;   -- immutable
  end if;

  if new.status = 'sent' and (tg_op = 'INSERT' or old.status = 'draft') then
    select status into v_rfq_status from public.rfqs where id = new.rfq_id;
    if v_rfq_status not in ('open', 'boqs_received', 'under_review') then
      raise exception 'This RFQ is no longer accepting BOQs.';
    end if;
    if not exists (select 1 from public.quotation_items where quotation_id = new.id) then
      raise exception 'Price at least one line item before sending the BOQ.';
    end if;
    if new.delivery_date is null then
      raise exception 'A delivery date is required.';
    end if;
    if new.delivery_date < current_date then
      raise exception 'The delivery date cannot be in the past.';
    end if;
    if new.valid_until is not null and new.valid_until < current_date then
      raise exception 'The "valid until" date cannot be in the past.';
    end if;
    new.sent_at := now();
  end if;

  if new.status in ('accepted', 'rejected') and (tg_op = 'INSERT' or old.status is distinct from new.status) then
    new.decided_at := coalesce(new.decided_at, now());
  end if;

  return new;
end;
$$;

create trigger quotations_lifecycle_before_write
  before insert or update on public.quotations
  for each row execute function private.quotations_lifecycle();

-- First BOQ sent -> RFQ moves from Open to "BOQs Received"
create or replace function private.quotations_after_sent()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  update public.rfqs set status = 'boqs_received'
  where id = new.rfq_id and status = 'open';
  return null;
end;
$$;

create trigger quotations_after_sent
  after update of status on public.quotations
  for each row
  when (old.status = 'draft' and new.status = 'sent')
  execute function private.quotations_after_sent();

-- Quotation items: validate ownership + snapshot the product name
create or replace function private.quotation_items_lifecycle()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_rfq_id      uuid;
  v_supplier_id uuid;
  v_product     text;
begin
  select q.rfq_id, q.supplier_id into v_rfq_id, v_supplier_id
  from public.quotations q where q.id = new.quotation_id;

  if not exists (select 1 from public.rfq_items where id = new.rfq_item_id and rfq_id = v_rfq_id) then
    raise exception 'A BOQ line does not belong to this RFQ.';
  end if;

  if new.product_id is not null
     and (tg_op = 'INSERT' or new.product_id is distinct from old.product_id) then
    select name into v_product from public.products
    where id = new.product_id and supplier_id = v_supplier_id;
    if v_product is null then
      raise exception 'You can only quote products from your own catalogue.';
    end if;
    new.product_name := v_product;
  elsif tg_op = 'INSERT' then
    new.product_name := null;
  end if;

  if new.delivery_date is not null and new.delivery_date < current_date
     and (tg_op = 'INSERT' or new.delivery_date is distinct from old.delivery_date) then
    raise exception 'A line delivery date cannot be in the past.';
  end if;

  return new;
end;
$$;

create trigger quotation_items_lifecycle_before_write
  before insert or update on public.quotation_items
  for each row execute function private.quotation_items_lifecycle();

-- Keep quotations.total_amount = sum(line_total)
create or replace function private.on_quotation_items_changed()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    update public.quotations q
       set total_amount = coalesce((select sum(qi.line_total) from public.quotation_items qi where qi.quotation_id = q.id), 0)
     where q.id in (select distinct o.quotation_id from old_rows o);
  else
    update public.quotations q
       set total_amount = coalesce((select sum(qi.line_total) from public.quotation_items qi where qi.quotation_id = q.id), 0)
     where q.id in (select distinct n.quotation_id from new_rows n);
  end if;
  return null;
end;
$$;

create trigger quotation_items_total_after_insert
  after insert on public.quotation_items referencing new table as new_rows
  for each statement execute function private.on_quotation_items_changed();
create trigger quotation_items_total_after_update
  after update on public.quotation_items referencing new table as new_rows
  for each statement execute function private.on_quotation_items_changed();
create trigger quotation_items_total_after_delete
  after delete on public.quotation_items referencing old table as old_rows
  for each statement execute function private.on_quotation_items_changed();

-- -----------------------------------------------------------------------------
-- Back-fill profiles for auth users that existed before this migration
-- (only users whose metadata role is contractor/supplier and company is valid)
-- -----------------------------------------------------------------------------
do $$
declare
  u record;
  v_role public.user_role;
  v_company text;
begin
  for u in
    select au.id, au.email, au.raw_user_meta_data as meta
    from auth.users au
    where not exists (select 1 from public.profiles p where p.id = au.id)
      and lower(coalesce(au.raw_user_meta_data ->> 'role', '')) in ('contractor', 'supplier')
  loop
    v_role := lower(u.meta ->> 'role')::public.user_role;
    v_company := btrim(regexp_replace(regexp_replace(coalesce(u.meta ->> 'company_name', ''), '[[:cntrl:]]', '', 'g'), '\s+', ' ', 'g'));
    if char_length(v_company) between 2 and 120 then
      insert into public.profiles (id, role, company_name, email, alias_code)
      values (u.id, v_role, v_company, u.email, private.generate_alias_code(v_role));
    end if;
  end loop;
end
$$;
