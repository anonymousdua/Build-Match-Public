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
