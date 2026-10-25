-- BuildMatch · all-in-one (migrations 01–05). Paste into Supabase → SQL Editor and Run.
-- If you still have the earlier prototype profiles table, run migrations/20261025090000_reset_legacy_profiles.sql first.

-- =============================================================================
-- BuildMatch · 01 · Schema: enums, reference data, tables, constraints, indexes
-- =============================================================================

-- Internal helpers live in `private`, which PostgREST does NOT expose,
-- so none of them can be called as an RPC from the app.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

-- -----------------------------------------------------------------------------
-- Text helpers used by CHECK constraints and generated columns
-- -----------------------------------------------------------------------------

-- True when the value is NULL, or is already trimmed and has no control
-- characters. Multiline fields may contain \n, \r and \t.
create or replace function private.is_clean_text(p_value text, p_multiline boolean default false)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select p_value is null or (
    p_value = pg_catalog.btrim(p_value, E' \t\r\n')
    and p_value !~ (case
                      when p_multiline then E'[\\x01-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F]'
                      else E'[\\x01-\\x1F\\x7F]'
                    end)
  );
$$;

-- Normalised keyword set used for RFQ ⇄ product matching.
-- Lower-cases, splits on anything that is not a letter/digit, drops short
-- tokens, pure sizes/quantities ("16mm", "200", "4m", "2kw") and filler words.
-- Example: 'Rebar B500B 16mm' -> {b500b, rebar}
create or replace function private.search_tokens(p_value text)
returns text[]
language sql
immutable
parallel safe
set search_path = ''
as $$
  select coalesce(array_agg(distinct tok order by tok), '{}'::text[])
  from pg_catalog.regexp_split_to_table(pg_catalog.lower(coalesce(p_value, '')), '[^[:alnum:]]+') as tok
  where pg_catalog.char_length(tok) >= 3
    and tok !~ '^[0-9]+([.][0-9]+)?(mm|cm|m|km|kg|kn|mpa|n|w|kw|v|a|l|ltr|pcs)?$'
    and tok <> all (array['and', 'the', 'for', 'with', 'per', 'type', 'grade', 'class', 'size',
                          'supply', 'standard', 'new']);
$$;

grant execute on function private.is_clean_text(text, boolean) to authenticated;
grant execute on function private.search_tokens(text) to authenticated;

-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------
create type public.user_role as enum ('contractor', 'supplier');

-- UI labels: Draft · Open · BOQs Received · Under Review · Supplier Hired · Not Hired / Closed
create type public.rfq_status as enum ('draft', 'open', 'boqs_received', 'under_review', 'hired', 'closed');

-- UI labels: Draft · Sent · Viewed · Shortlisted · Accepted · Rejected
create type public.quotation_status as enum ('draft', 'sent', 'viewed', 'shortlisted', 'accepted', 'rejected');

-- "Not supplied" = no quotation_items row for that RFQ line.
create type public.item_availability as enum ('in_stock', 'partial', 'on_order');

-- UI shows m2 / m3 as m² / m³
create type public.unit_type as enum ('bag', 'ton', 'kg', 'm', 'm2', 'm3', 'pcs', 'roll', 'litre', 'set', 'lot');

-- -----------------------------------------------------------------------------
-- Categories (reference data, shared dropdown for products and RFQ items)
-- -----------------------------------------------------------------------------
create table public.categories (
  id          text primary key check (id ~ '^[a-z0-9-]{2,40}$'),
  name        text not null unique check (char_length(name) between 2 and 60),
  sort_order  smallint not null default 0,
  created_at  timestamptz not null default now()
);

insert into public.categories (id, name, sort_order) values
  ('cement-concrete',  'Cement & Concrete',   10),
  ('steel-rebar',      'Steel & Rebar',       20),
  ('structural-steel', 'Structural Steel',    30),
  ('aggregates',       'Aggregates',          40),
  ('masonry',          'Masonry',             50),
  ('timber',           'Timber',              60),
  ('finishes',         'Finishes',            70),
  ('plumbing',         'Plumbing',            80),
  ('electrical',       'Electrical',          90),
  ('hvac',             'HVAC',               100),
  ('fixings',          'Fixings & Fasteners',110),
  ('other',            'Other',              999)
on conflict (id) do nothing;

-- -----------------------------------------------------------------------------
-- Profiles (1:1 with auth.users). company_name / email are IDENTIFYING and are
-- only ever returned to their owner, or to the counter-party after a reveal.
-- -----------------------------------------------------------------------------
create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  role          public.user_role not null,
  company_name  text not null
                check (char_length(company_name) between 2 and 120
                       and private.is_clean_text(company_name)),
  email         text check (email is null or char_length(email) <= 254),
  alias_code    text not null unique check (alias_code ~ '^[CS]-[0-9]{4,6}$'),
  -- e.g. 'Contractor #C-4821' / 'Supplier #S-1093'
  alias         text generated always as (
                  case role when 'contractor' then 'Contractor #' else 'Supplier #' end || alias_code
                ) stored,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint profiles_alias_prefix_matches_role check (
    (role = 'contractor' and alias_code like 'C-%') or
    (role = 'supplier'   and alias_code like 'S-%')
  )
);

-- -----------------------------------------------------------------------------
-- RFQs
-- -----------------------------------------------------------------------------
create table public.rfqs (
  id                  uuid primary key default gen_random_uuid(),
  ref_no              bigint generated always as identity (start with 2001) unique,  -- shown as RFQ-2041
  contractor_id       uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  title               text not null
                      check (char_length(title) between 3 and 150 and private.is_clean_text(title)),
  description         text
                      check (description is null or (char_length(description) <= 4000
                             and private.is_clean_text(description, true))),
  delivery_location   text not null   -- city / region only, never a full address
                      check (char_length(delivery_location) between 2 and 120
                             and private.is_clean_text(delivery_location)),
  required_by         date not null,
  status              public.rfq_status not null default 'draft',
  hired_quotation_id  uuid,           -- FK added after quotations exists
  published_at        timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index rfqs_contractor_created_idx on public.rfqs (contractor_id, created_at desc);
create index rfqs_status_idx on public.rfqs (status);

create table public.rfq_items (
  id             uuid primary key default gen_random_uuid(),
  rfq_id         uuid not null references public.rfqs (id) on delete cascade,
  line_no        integer not null check (line_no between 1 and 500),
  item_name      text not null
                 check (char_length(item_name) between 1 and 150 and private.is_clean_text(item_name)),
  category_id    text not null references public.categories (id) on update cascade,
  specification  text
                 check (specification is null or (char_length(specification) <= 300
                        and private.is_clean_text(specification))),
  quantity       numeric(14, 3) not null check (quantity > 0 and quantity <= 1000000000),
  unit           public.unit_type not null,
  search_tokens  text[] generated always as (private.search_tokens(item_name)) stored,
  created_at     timestamptz not null default now(),
  unique (rfq_id, line_no)
);

create index rfq_items_rfq_idx on public.rfq_items (rfq_id);
create index rfq_items_category_idx on public.rfq_items (category_id);
create index rfq_items_tokens_idx on public.rfq_items using gin (search_tokens);

-- Metadata for files in the private `rfq-attachments` bucket (path: <rfq_id>/<file>)
create table public.rfq_attachments (
  id            uuid primary key default gen_random_uuid(),
  rfq_id        uuid not null references public.rfqs (id) on delete cascade,
  storage_path  text not null unique
                check (char_length(storage_path) between 3 and 300 and private.is_clean_text(storage_path)),
  file_name     text not null
                check (char_length(file_name) between 1 and 200 and private.is_clean_text(file_name)),
  size_bytes    bigint not null check (size_bytes > 0 and size_bytes <= 26214400),   -- 25 MB
  mime_type     text not null check (char_length(mime_type) <= 120),
  created_at    timestamptz not null default now()
);

create index rfq_attachments_rfq_idx on public.rfq_attachments (rfq_id);

-- -----------------------------------------------------------------------------
-- Supplier products
-- -----------------------------------------------------------------------------
create table public.products (
  id                  uuid primary key default gen_random_uuid(),
  supplier_id         uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  name                text not null
                      check (char_length(name) between 2 and 150 and private.is_clean_text(name)),
  category_id         text not null references public.categories (id) on update cascade,
  description         text
                      check (description is null or (char_length(description) <= 2000
                             and private.is_clean_text(description, true))),
  specifications      text
                      check (specifications is null or (char_length(specifications) <= 1000
                             and private.is_clean_text(specifications, true))),
  unit                public.unit_type not null,
  available_quantity  numeric(14, 3) check (available_quantity is null or (available_quantity >= 0
                                            and available_quantity <= 1000000000)),
  price_min           numeric(12, 2) check (price_min is null or (price_min > 0 and price_min <= 100000000)),
  price_max           numeric(12, 2) check (price_max is null or (price_max > 0 and price_max <= 100000000)),
  lead_time_days      integer check (lead_time_days is null or lead_time_days between 0 and 365),
  is_active           boolean not null default true,    -- "availability" toggle
  image_path          text check (image_path is null or (char_length(image_path) <= 300
                                  and private.is_clean_text(image_path))),
  search_tokens       text[] generated always as (private.search_tokens(name)) stored,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint products_price_range_valid check (price_min is null or price_max is null or price_min <= price_max)
);

create unique index products_supplier_name_uidx on public.products (supplier_id, lower(name));
create index products_category_idx on public.products (category_id);
create index products_tokens_idx on public.products using gin (search_tokens);

-- -----------------------------------------------------------------------------
-- Matches (written only by the matching engine)
-- -----------------------------------------------------------------------------
create table public.matches (
  rfq_id         uuid not null references public.rfqs (id) on delete cascade,
  supplier_id    uuid not null references public.profiles (id) on delete cascade,
  matched_items  integer not null check (matched_items >= 0),
  total_items    integer not null check (total_items >= 0),
  score          numeric(5, 2) not null check (score between 0 and 100),   -- the "94%" badge
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  primary key (rfq_id, supplier_id)
);

create index matches_supplier_created_idx on public.matches (supplier_id, created_at desc);

-- -----------------------------------------------------------------------------
-- Quotations (BOQs) and their line items
-- -----------------------------------------------------------------------------
create table public.quotations (
  id             uuid primary key default gen_random_uuid(),
  rfq_id         uuid not null references public.rfqs (id) on delete cascade,
  supplier_id    uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  ref_seq        integer not null,               -- shown as BOQ-<rfq ref>-<seq>, e.g. BOQ-2041-1
  status         public.quotation_status not null default 'draft',
  total_amount   numeric(16, 2) not null default 0 check (total_amount >= 0),   -- maintained by trigger
  currency       text not null default 'AED' check (currency = 'AED'),
  delivery_date  date,
  valid_until    date,
  notes          text
                 check (notes is null or (char_length(notes) <= 2000 and private.is_clean_text(notes, true))),
  sent_at        timestamptz,
  decided_at     timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (rfq_id, supplier_id),                  -- one BOQ per supplier per RFQ
  unique (rfq_id, ref_seq),
  constraint quotations_sent_needs_delivery check (status = 'draft' or delivery_date is not null)
);

create index quotations_rfq_idx on public.quotations (rfq_id);
create index quotations_supplier_created_idx on public.quotations (supplier_id, created_at desc);

alter table public.rfqs
  add constraint rfqs_hired_quotation_fk
  foreign key (hired_quotation_id) references public.quotations (id) on delete set null;

create table public.quotation_items (
  id             uuid primary key default gen_random_uuid(),
  quotation_id   uuid not null references public.quotations (id) on delete cascade,
  rfq_item_id    uuid not null references public.rfq_items (id) on delete cascade,
  product_id     uuid references public.products (id) on delete set null,
  product_name   text check (product_name is null or char_length(product_name) <= 150),  -- snapshot
  quantity       numeric(14, 3) not null check (quantity > 0 and quantity <= 1000000000),
  unit_price     numeric(12, 2) not null check (unit_price > 0 and unit_price <= 100000000),
  line_total     numeric(18, 2) generated always as (round(quantity * unit_price, 2)) stored,
  availability   public.item_availability not null default 'in_stock',
  delivery_date  date,
  created_at     timestamptz not null default now(),
  unique (quotation_id, rfq_item_id)
);

create index quotation_items_quotation_idx on public.quotation_items (quotation_id);
create index quotation_items_rfq_item_idx on public.quotation_items (rfq_item_id);
create index quotation_items_product_idx on public.quotation_items (product_id);

-- -----------------------------------------------------------------------------
-- Reveals: one row per accepted quotation. Its existence is what unlocks
-- company name + email for both parties of THAT rfq/quotation only.
-- -----------------------------------------------------------------------------
create table public.reveals (
  id             uuid primary key default gen_random_uuid(),
  rfq_id         uuid not null unique references public.rfqs (id) on delete cascade,
  quotation_id   uuid not null unique references public.quotations (id) on delete cascade,
  contractor_id  uuid not null references public.profiles (id) on delete cascade,
  supplier_id    uuid not null references public.profiles (id) on delete cascade,
  revealed_at    timestamptz not null default now()
);

create index reveals_contractor_idx on public.reveals (contractor_id);
create index reveals_supplier_idx on public.reveals (supplier_id);

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

-- =============================================================================
-- BuildMatch · 04 · RPC functions called from the app (supabase.rpc(...))
--
-- * Write RPCs that the caller is allowed to do anyway (save_rfq,
--   submit_quotation) are SECURITY INVOKER, so RLS + guards still apply.
-- * Contractor decisions and all cross-party reads are SECURITY DEFINER and
--   check ownership explicitly. They return ALIASES ONLY, plus company name /
--   email exclusively when a `reveals` row exists for that RFQ + quotation.
-- * Parameters only; no dynamic SQL.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- CONTRACTOR · create / update an RFQ with its line items in one call
--   p_items: [{"item_name":"Rebar 16mm","category_id":"steel-rebar",
--              "specification":"B500B, 12m","quantity":85,"unit":"ton"}, ...]
--   p_publish = false -> "Save draft", true -> "Publish RFQ"
--   p_rfq_id  = null  -> create, otherwise update that RFQ (replaces items)
-- -----------------------------------------------------------------------------
create or replace function public.save_rfq(
  p_title              text,
  p_description        text,
  p_delivery_location  text,
  p_required_by        date,
  p_items              jsonb,
  p_publish            boolean default false,
  p_rfq_id             uuid    default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if private.current_user_role() is distinct from 'contractor' then
    raise exception 'Only contractors can create RFQs.';
  end if;
  if p_items is null or pg_catalog.jsonb_typeof(p_items) <> 'array' then
    raise exception 'Line items are invalid.';
  end if;
  if pg_catalog.jsonb_array_length(p_items) > 200 then
    raise exception 'An RFQ can have at most 200 line items.';
  end if;
  if p_publish and pg_catalog.jsonb_array_length(p_items) = 0 then
    raise exception 'Add at least one line item before publishing the RFQ.';
  end if;

  if p_rfq_id is null then
    insert into public.rfqs (title, description, delivery_location, required_by)
    values (pg_catalog.btrim(p_title),
            nullif(pg_catalog.btrim(p_description), ''),
            pg_catalog.btrim(p_delivery_location),
            p_required_by)
    returning id into v_id;
  else
    if not private.rfq_is_editable(p_rfq_id) then
      raise exception 'This RFQ can no longer be edited.';
    end if;
    update public.rfqs
       set title             = pg_catalog.btrim(p_title),
           description       = nullif(pg_catalog.btrim(p_description), ''),
           delivery_location = pg_catalog.btrim(p_delivery_location),
           required_by       = p_required_by
     where id = p_rfq_id
    returning id into v_id;
    if v_id is null then
      raise exception 'RFQ not found.';
    end if;
    delete from public.rfq_items where rfq_id = v_id;
  end if;

  begin
    insert into public.rfq_items (rfq_id, line_no, item_name, category_id, specification, quantity, unit)
    select v_id,
           x.ord::int,
           pg_catalog.btrim(x.item ->> 'item_name'),
           x.item ->> 'category_id',
           nullif(pg_catalog.btrim(x.item ->> 'specification'), ''),
           (x.item ->> 'quantity')::numeric,
           (x.item ->> 'unit')::public.unit_type
    from pg_catalog.jsonb_array_elements(p_items) with ordinality as x(item, ord);
  exception
    when invalid_text_representation or numeric_value_out_of_range or not_null_violation then
      raise exception 'Every line item needs a name, category, positive quantity and unit.';
    when foreign_key_violation then
      raise exception 'A line item has an unknown category.';
  end;

  if p_publish then
    update public.rfqs set status = 'open' where id = v_id and status = 'draft';
  end if;

  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- CONTRACTOR · list own RFQs with counts (My RFQs + Recent RFQs)
-- -----------------------------------------------------------------------------
create or replace function public.get_my_rfqs()
returns table (
  id                      uuid,
  rfq_code                text,
  title                   text,
  description             text,
  delivery_location       text,
  required_by             date,
  status                  public.rfq_status,
  created_at              timestamptz,
  published_at            timestamptz,
  item_count              integer,
  boq_count               integer,
  matched_supplier_count  integer
)
language sql stable security definer set search_path = ''
as $$
  select r.id,
         'RFQ-' || r.ref_no,
         r.title, r.description, r.delivery_location, r.required_by, r.status,
         r.created_at, r.published_at,
         (select count(*)::int from public.rfq_items i  where i.rfq_id = r.id),
         (select count(*)::int from public.quotations q where q.rfq_id = r.id and q.status <> 'draft'),
         (select count(*)::int from public.matches m    where m.rfq_id = r.id)
  from public.rfqs r
  where r.contractor_id = auth.uid()
  order by r.created_at desc;
$$;

-- -----------------------------------------------------------------------------
-- CONTRACTOR · dashboard stat cards
-- -----------------------------------------------------------------------------
create or replace function public.get_contractor_stats()
returns table (
  total_rfqs      integer,
  open_rfqs       integer,   -- open + boqs_received + under_review ("Awaiting decision")
  boqs_received   integer,
  boqs_this_week  integer,
  hired_rfqs      integer
)
language sql stable security definer set search_path = ''
as $$
  select
    (select count(*)::int from public.rfqs r where r.contractor_id = auth.uid()),
    (select count(*)::int from public.rfqs r where r.contractor_id = auth.uid()
                                             and r.status in ('open', 'boqs_received', 'under_review')),
    (select count(*)::int from public.quotations q join public.rfqs r on r.id = q.rfq_id
      where r.contractor_id = auth.uid() and q.status <> 'draft'),
    (select count(*)::int from public.quotations q join public.rfqs r on r.id = q.rfq_id
      where r.contractor_id = auth.uid() and q.status <> 'draft' and q.sent_at >= now() - interval '7 days'),
    (select count(*)::int from public.rfqs r where r.contractor_id = auth.uid() and r.status = 'hired');
$$;

-- -----------------------------------------------------------------------------
-- CONTRACTOR · all BOQs received on one of my RFQs (detail page + comparison)
--   items: [{rfq_item_id, product_name, quantity, unit_price, line_total,
--            availability, delivery_date}]  (missing rfq_item_id = not supplied)
--   supplier_company_name / supplier_email are NULL until that BOQ is accepted.
-- -----------------------------------------------------------------------------
create or replace function public.get_rfq_quotations(p_rfq_id uuid)
returns table (
  quotation_id           uuid,
  boq_code               text,
  supplier_alias         text,
  status                 public.quotation_status,
  total_amount           numeric,
  currency               text,
  delivery_date          date,
  valid_until            date,
  notes                  text,
  sent_at                timestamptz,
  covered_items          integer,
  total_items            integer,
  items                  jsonb,
  is_revealed            boolean,
  supplier_company_name  text,
  supplier_email         text
)
language sql stable security definer set search_path = ''
as $$
  select q.id,
         'BOQ-' || r.ref_no || '-' || q.ref_seq,
         p.alias,
         q.status, q.total_amount, q.currency, q.delivery_date, q.valid_until, q.notes, q.sent_at,
         (select count(*)::int from public.quotation_items qi where qi.quotation_id = q.id),
         (select count(*)::int from public.rfq_items ri where ri.rfq_id = r.id),
         coalesce((
           select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                    'rfq_item_id',   qi.rfq_item_id,
                    'product_name',  qi.product_name,
                    'quantity',      qi.quantity,
                    'unit_price',    qi.unit_price,
                    'line_total',    qi.line_total,
                    'availability',  qi.availability,
                    'delivery_date', qi.delivery_date) order by ri.line_no)
           from public.quotation_items qi
           join public.rfq_items ri on ri.id = qi.rfq_item_id
           where qi.quotation_id = q.id), '[]'::jsonb),
         rv.id is not null,
         case when rv.id is not null then p.company_name end,
         case when rv.id is not null then p.email end
  from public.rfqs r
  join public.quotations q on q.rfq_id = r.id and q.status <> 'draft'
  join public.profiles p   on p.id = q.supplier_id
  left join public.reveals rv on rv.quotation_id = q.id
  where r.id = p_rfq_id
    and r.contractor_id = auth.uid()
  order by q.total_amount, q.sent_at;
$$;

-- -----------------------------------------------------------------------------
-- CONTRACTOR · decisions on a BOQ
-- -----------------------------------------------------------------------------

-- "View BOQ": Sent -> Viewed (no-op otherwise)
create or replace function public.mark_quotation_viewed(p_quotation_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update public.quotations q
     set status = 'viewed'
    from public.rfqs r
   where q.id = p_quotation_id
     and r.id = q.rfq_id
     and r.contractor_id = auth.uid()
     and q.status = 'sent';
end;
$$;

-- Star toggle: Sent/Viewed <-> Shortlisted
create or replace function public.set_quotation_shortlisted(p_quotation_id uuid, p_shortlisted boolean)
returns public.quotation_status
language plpgsql security definer set search_path = ''
as $$
declare
  v_status     public.quotation_status;
  v_rfq_status public.rfq_status;
begin
  select q.status, r.status into v_status, v_rfq_status
  from public.quotations q
  join public.rfqs r on r.id = q.rfq_id
  where q.id = p_quotation_id and r.contractor_id = auth.uid() and q.status <> 'draft'
  for update of q;

  if v_status is null then
    raise exception 'BOQ not found.';
  end if;
  if v_rfq_status in ('hired', 'closed') or v_status in ('accepted', 'rejected') then
    raise exception 'This BOQ has already been decided.';
  end if;

  if p_shortlisted and v_status in ('sent', 'viewed') then
    v_status := 'shortlisted';
  elsif not p_shortlisted and v_status = 'shortlisted' then
    v_status := 'viewed';
  end if;

  update public.quotations set status = v_status where id = p_quotation_id;
  return v_status;
end;
$$;

-- "Mark as hired": accept this BOQ, reject the others, hire, reveal identities.
-- Returns the supplier's contact details.
create or replace function public.accept_quotation(p_quotation_id uuid)
returns table (supplier_alias text, supplier_company_name text, supplier_email text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_rfq_id      uuid;
  v_supplier_id uuid;
  v_q_status    public.quotation_status;
  v_rfq_status  public.rfq_status;
begin
  select q.rfq_id, q.supplier_id, q.status, r.status
    into v_rfq_id, v_supplier_id, v_q_status, v_rfq_status
  from public.quotations q
  join public.rfqs r on r.id = q.rfq_id
  where q.id = p_quotation_id and r.contractor_id = auth.uid()
  for update of q, r;

  if v_rfq_id is null then
    raise exception 'BOQ not found.';
  end if;
  if v_rfq_status not in ('open', 'boqs_received', 'under_review') then
    raise exception 'This RFQ is already finalised.';
  end if;
  if v_q_status not in ('sent', 'viewed', 'shortlisted') then
    raise exception 'This BOQ cannot be accepted.';
  end if;

  update public.quotations set status = 'accepted' where id = p_quotation_id;

  update public.quotations
     set status = 'rejected'
   where rfq_id = v_rfq_id
     and id <> p_quotation_id
     and status in ('sent', 'viewed', 'shortlisted');

  update public.rfqs
     set status = 'hired', hired_quotation_id = p_quotation_id
   where id = v_rfq_id;

  insert into public.reveals (rfq_id, quotation_id, contractor_id, supplier_id)
  values (v_rfq_id, p_quotation_id, auth.uid(), v_supplier_id);

  return query
    select p.alias, p.company_name, p.email
    from public.profiles p where p.id = v_supplier_id;
end;
$$;

create or replace function public.reject_quotation(p_quotation_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update public.quotations q
     set status = 'rejected'
    from public.rfqs r
   where q.id = p_quotation_id
     and r.id = q.rfq_id
     and r.contractor_id = auth.uid()
     and q.status in ('sent', 'viewed', 'shortlisted');

  if not found then
    raise exception 'This BOQ cannot be rejected.';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- SUPPLIER · dashboard stat cards
-- -----------------------------------------------------------------------------
create or replace function public.get_supplier_stats()
returns table (
  total_products     integer,
  matched_rfqs       integer,
  matched_last_24h   integer,
  boqs_sent          integer,
  boqs_accepted      integer
)
language sql stable security definer set search_path = ''
as $$
  select
    (select count(*)::int from public.products p   where p.supplier_id = auth.uid()),
    (select count(*)::int from public.matches m    where m.supplier_id = auth.uid()),
    (select count(*)::int from public.matches m    where m.supplier_id = auth.uid()
                                                   and m.created_at >= now() - interval '24 hours'),
    (select count(*)::int from public.quotations q where q.supplier_id = auth.uid() and q.status <> 'draft'),
    (select count(*)::int from public.quotations q where q.supplier_id = auth.uid() and q.status = 'accepted');
$$;

-- -----------------------------------------------------------------------------
-- SUPPLIER · Matched RFQs list (contractor shown by alias only)
-- -----------------------------------------------------------------------------
create or replace function public.get_matched_rfqs()
returns table (
  rfq_id             uuid,
  rfq_code           text,
  title              text,
  delivery_location  text,
  required_by        date,
  rfq_status         public.rfq_status,
  contractor_alias   text,
  item_count         integer,
  match_score        numeric,
  matched_at         timestamptz,
  quotation_id       uuid,
  quotation_status   public.quotation_status
)
language sql stable security definer set search_path = ''
as $$
  select r.id,
         'RFQ-' || r.ref_no,
         r.title, r.delivery_location, r.required_by, r.status,
         p.alias,
         (select count(*)::int from public.rfq_items i where i.rfq_id = r.id),
         m.score, m.created_at,
         q.id, q.status
  from public.matches m
  join public.rfqs r     on r.id = m.rfq_id
  join public.profiles p on p.id = r.contractor_id
  left join public.quotations q on q.rfq_id = r.id and q.supplier_id = m.supplier_id
  where m.supplier_id = auth.uid()
  order by m.created_at desc;
$$;

-- -----------------------------------------------------------------------------
-- SUPPLIER · one matched RFQ (Create BOQ page). Returns NULL if not matched.
--   items[].suggested_product_ids = my active products that matched that line
--   my_quotation = my draft/sent BOQ for it (or null)
--   revealed_contact = contractor company/email, only after my BOQ was accepted
-- -----------------------------------------------------------------------------
create or replace function public.get_supplier_rfq(p_rfq_id uuid)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'rfq_id',            r.id,
    'rfq_code',          'RFQ-' || r.ref_no,
    'title',             r.title,
    'description',       r.description,
    'delivery_location', r.delivery_location,
    'required_by',       r.required_by,
    'status',            r.status,
    'contractor_alias',  p.alias,
    'match_score',       m.score,
    'items', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'id',            i.id,
               'line_no',       i.line_no,
               'item_name',     i.item_name,
               'category_id',   i.category_id,
               'specification', i.specification,
               'quantity',      i.quantity,
               'unit',          i.unit,
               'suggested_product_ids', coalesce((
                  select pg_catalog.jsonb_agg(pr.id order by pr.name)
                  from public.products pr
                  where pr.supplier_id = auth.uid()
                    and pr.is_active
                    and pr.category_id = i.category_id
                    and pr.search_tokens && i.search_tokens), '[]'::jsonb)
             ) order by i.line_no)
      from public.rfq_items i where i.rfq_id = r.id), '[]'::jsonb),
    'my_quotation', (
      select pg_catalog.jsonb_build_object(
               'id',            q.id,
               'boq_code',      'BOQ-' || r.ref_no || '-' || q.ref_seq,
               'status',        q.status,
               'total_amount',  q.total_amount,
               'delivery_date', q.delivery_date,
               'valid_until',   q.valid_until,
               'notes',         q.notes,
               'items', coalesce((
                  select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                           'rfq_item_id',   qi.rfq_item_id,
                           'product_id',    qi.product_id,
                           'product_name',  qi.product_name,
                           'quantity',      qi.quantity,
                           'unit_price',    qi.unit_price,
                           'line_total',    qi.line_total,
                           'availability',  qi.availability,
                           'delivery_date', qi.delivery_date))
                  from public.quotation_items qi where qi.quotation_id = q.id), '[]'::jsonb))
      from public.quotations q
      where q.rfq_id = r.id and q.supplier_id = auth.uid()),
    'revealed_contact', (
      select pg_catalog.jsonb_build_object('company_name', p.company_name, 'email', p.email)
      from public.reveals rv
      where rv.rfq_id = r.id and rv.supplier_id = auth.uid())
  )
  from public.matches m
  join public.rfqs r     on r.id = m.rfq_id
  join public.profiles p on p.id = r.contractor_id
  where m.rfq_id = p_rfq_id
    and m.supplier_id = auth.uid();
$$;

-- -----------------------------------------------------------------------------
-- SUPPLIER · save or send a BOQ in one call (SECURITY INVOKER -> RLS applies)
--   p_items: [{"rfq_item_id":"…","product_id":"…","quantity":18,
--              "unit_price":2550,"availability":"in_stock",
--              "delivery_date":"2027-01-15"}, ...]
--   Omit an RFQ line to mark it "Not supplied".
--   p_send = false -> "Save draft", true -> "Send BOQ"
-- -----------------------------------------------------------------------------
create or replace function public.submit_quotation(
  p_rfq_id         uuid,
  p_items          jsonb,
  p_delivery_date  date,
  p_valid_until    date    default null,
  p_notes          text    default null,
  p_send           boolean default false
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id     uuid;
  v_status public.quotation_status;
begin
  if private.current_user_role() is distinct from 'supplier' then
    raise exception 'Only suppliers can send BOQs.';
  end if;
  if p_items is null or pg_catalog.jsonb_typeof(p_items) <> 'array' then
    raise exception 'BOQ lines are invalid.';
  end if;
  if pg_catalog.jsonb_array_length(p_items) > 500 then
    raise exception 'Too many BOQ lines.';
  end if;
  if p_send and pg_catalog.jsonb_array_length(p_items) = 0 then
    raise exception 'Price at least one line item before sending the BOQ.';
  end if;

  select q.id, q.status into v_id, v_status
  from public.quotations q
  where q.rfq_id = p_rfq_id and q.supplier_id = auth.uid();

  if v_id is null then
    insert into public.quotations (rfq_id, delivery_date, valid_until, notes)
    values (p_rfq_id, p_delivery_date, p_valid_until, nullif(pg_catalog.btrim(p_notes), ''))
    returning id into v_id;
  else
    if v_status <> 'draft' then
      raise exception 'This BOQ has already been sent and can no longer be changed.';
    end if;
    update public.quotations
       set delivery_date = p_delivery_date,
           valid_until   = p_valid_until,
           notes         = nullif(pg_catalog.btrim(p_notes), '')
     where id = v_id;
    delete from public.quotation_items where quotation_id = v_id;
  end if;

  begin
    insert into public.quotation_items (quotation_id, rfq_item_id, product_id, quantity, unit_price, availability, delivery_date)
    select v_id,
           (x ->> 'rfq_item_id')::uuid,
           nullif(x ->> 'product_id', '')::uuid,
           (x ->> 'quantity')::numeric,
           (x ->> 'unit_price')::numeric,
           coalesce(nullif(x ->> 'availability', '')::public.item_availability, 'in_stock'),
           nullif(x ->> 'delivery_date', '')::date
    from pg_catalog.jsonb_array_elements(p_items) as x;
  exception
    when invalid_text_representation or invalid_datetime_format or datetime_field_overflow
         or numeric_value_out_of_range or not_null_violation then
      raise exception 'Every priced line needs a valid quantity, unit price and date.';
    when unique_violation then
      raise exception 'Each RFQ line can only be priced once.';
  end;

  if p_send then
    update public.quotations set status = 'sent' where id = v_id;
  end if;

  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- SUPPLIER · My BOQs list + detail modal
--   items lists EVERY RFQ line; offered fields are null when not supplied.
--   contractor_company_name / contractor_email only after acceptance.
-- -----------------------------------------------------------------------------
create or replace function public.get_my_quotations()
returns table (
  quotation_id             uuid,
  boq_code                 text,
  rfq_id                   uuid,
  rfq_code                 text,
  rfq_title                text,
  contractor_alias         text,
  status                   public.quotation_status,
  total_amount             numeric,
  currency                 text,
  delivery_date            date,
  valid_until              date,
  notes                    text,
  sent_at                  timestamptz,
  created_at               timestamptz,
  items                    jsonb,
  is_revealed              boolean,
  contractor_company_name  text,
  contractor_email         text
)
language sql stable security definer set search_path = ''
as $$
  select q.id,
         'BOQ-' || r.ref_no || '-' || q.ref_seq,
         r.id,
         'RFQ-' || r.ref_no,
         r.title,
         p.alias,
         q.status, q.total_amount, q.currency, q.delivery_date, q.valid_until, q.notes, q.sent_at, q.created_at,
         coalesce((
           select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                    'rfq_item_id',        ri.id,
                    'item_name',          ri.item_name,
                    'unit',               ri.unit,
                    'requested_quantity', ri.quantity,
                    'product_name',       qi.product_name,
                    'quantity',           qi.quantity,
                    'unit_price',         qi.unit_price,
                    'line_total',         qi.line_total,
                    'availability',       qi.availability,
                    'delivery_date',      qi.delivery_date) order by ri.line_no)
           from public.rfq_items ri
           left join public.quotation_items qi on qi.rfq_item_id = ri.id and qi.quotation_id = q.id
           where ri.rfq_id = r.id), '[]'::jsonb),
         rv.id is not null,
         case when rv.id is not null then p.company_name end,
         case when rv.id is not null then p.email end
  from public.quotations q
  join public.rfqs r     on r.id = q.rfq_id
  join public.profiles p on p.id = r.contractor_id
  left join public.reveals rv on rv.quotation_id = q.id
  where q.supplier_id = auth.uid()
  order by q.created_at desc;
$$;

-- -----------------------------------------------------------------------------
-- Execute privileges: signed-in users only
-- -----------------------------------------------------------------------------
revoke execute on function
  public.save_rfq(text, text, text, date, jsonb, boolean, uuid),
  public.get_my_rfqs(),
  public.get_contractor_stats(),
  public.get_rfq_quotations(uuid),
  public.mark_quotation_viewed(uuid),
  public.set_quotation_shortlisted(uuid, boolean),
  public.accept_quotation(uuid),
  public.reject_quotation(uuid),
  public.get_supplier_stats(),
  public.get_matched_rfqs(),
  public.get_supplier_rfq(uuid),
  public.submit_quotation(uuid, jsonb, date, date, text, boolean),
  public.get_my_quotations()
from public, anon;

grant execute on function
  public.save_rfq(text, text, text, date, jsonb, boolean, uuid),
  public.get_my_rfqs(),
  public.get_contractor_stats(),
  public.get_rfq_quotations(uuid),
  public.mark_quotation_viewed(uuid),
  public.set_quotation_shortlisted(uuid, boolean),
  public.accept_quotation(uuid),
  public.reject_quotation(uuid),
  public.get_supplier_stats(),
  public.get_matched_rfqs(),
  public.get_supplier_rfq(uuid),
  public.submit_quotation(uuid, jsonb, date, date, text, boolean),
  public.get_my_quotations()
to authenticated;

-- =============================================================================
-- BuildMatch · 05 · Storage buckets + policies (both buckets are PRIVATE)
--
--   rfq-attachments   path: <rfq_id>/<random-uuid>.<ext>
--                     contractor (owner) uploads/deletes while the RFQ is
--                     editable; owner + matched suppliers can download.
--   product-images    path: <supplier user id>/<random-uuid>.<ext>
--                     only the supplier who owns the folder.
--
-- Upload with a random file name (not the original) so file names never leak
-- a company name; keep the display name in public.rfq_attachments.file_name.
-- Download with createSignedUrl().
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('rfq-attachments', 'rfq-attachments', false, 26214400,
     array['application/pdf',
           'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
           'application/vnd.ms-excel',
           'image/vnd.dwg', 'application/acad', 'application/x-dwg', 'application/dwg']),
  ('product-images', 'product-images', false, 5242880,
     array['image/png', 'image/jpeg'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ---- rfq-attachments ---------------------------------------------------------
create policy "bm rfq-attachments: owner uploads while editable"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'rfq-attachments'
    and private.is_rfq_owner(private.try_uuid((storage.foldername(name))[1]))
    and private.rfq_is_editable(private.try_uuid((storage.foldername(name))[1]))
  );

create policy "bm rfq-attachments: owner or matched supplier downloads"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'rfq-attachments'
    and (private.is_rfq_owner(private.try_uuid((storage.foldername(name))[1]))
         or private.is_matched_supplier(private.try_uuid((storage.foldername(name))[1])))
  );

create policy "bm rfq-attachments: owner deletes while editable"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'rfq-attachments'
    and private.is_rfq_owner(private.try_uuid((storage.foldername(name))[1]))
    and private.rfq_is_editable(private.try_uuid((storage.foldername(name))[1]))
  );

-- ---- product-images ----------------------------------------------------------
create policy "bm product-images: supplier uploads to own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select private.current_user_role()) = 'supplier'
  );

create policy "bm product-images: supplier reads own folder"
  on storage.objects for select to authenticated
  using (bucket_id = 'product-images' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "bm product-images: supplier replaces in own folder"
  on storage.objects for update to authenticated
  using (bucket_id = 'product-images' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'product-images' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "bm product-images: supplier deletes own folder"
  on storage.objects for delete to authenticated
  using (bucket_id = 'product-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
