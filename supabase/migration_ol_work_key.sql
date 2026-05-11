-- Open Library Werk-ID (ein Werk = alle Sprachausgaben) für Vorschläge & Duplikat-Check
-- Im Supabase SQL Editor ausführen, falls die Tabelle schon ohne diese Spalte existiert.

alter table public.books add column if not exists open_library_work_key text;

create index if not exists books_ol_work_key_idx
  on public.books (open_library_work_key)
  where open_library_work_key is not null;
