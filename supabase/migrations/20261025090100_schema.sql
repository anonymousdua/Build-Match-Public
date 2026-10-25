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
