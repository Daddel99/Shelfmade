-- Einmal ausführen, wenn dein Projekt schon mit schema.sql angelegt wurde (bestehende Tabelle erweitern)

alter table public.books add column if not exists cover_url text;
alter table public.books add column if not exists rating smallint;

alter table public.books drop constraint if exists books_rating_range;
alter table public.books add constraint books_rating_range
  check (rating is null or (rating >= 1 and rating <= 5));
