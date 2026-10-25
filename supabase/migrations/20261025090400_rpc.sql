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
