-- Shelfmade: einmal im Supabase SQL Editor ausführen (Project → SQL → New query)

-- Profil pro Auth-User
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  username text not null unique,
  created_at timestamptz default now()
);

-- Bücher (pro Nutzer ein Regal)
create table if not exists public.books (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  author text not null,
  year int not null default 0,
  link text,
  cover_url text,
  rating smallint check (rating is null or (rating >= 1 and rating <= 5)),
  created_at timestamptz default now()
);

create index if not exists books_user_id_idx on public.books (user_id);

-- Freundschaften
create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  created_at timestamptz default now(),
  unique (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);

create index if not exists friendships_requester_idx on public.friendships (requester_id);
create index if not exists friendships_addressee_idx on public.friendships (addressee_id);

-- Lesegruppen (gemeinsame Bibliothek)
create table if not exists public.reading_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null default '',
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz default now()
);

create table if not exists public.reading_group_members (
  group_id uuid not null references public.reading_groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz default now(),
  primary key (group_id, user_id)
);

create index if not exists reading_group_members_user_idx on public.reading_group_members (user_id);
create index if not exists reading_group_members_group_idx on public.reading_group_members (group_id);

-- Neues Konto → Profilzeile
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  base text;
  uname text;
begin
  base := coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1));
  if base = '' or base is null then
    base := 'reader';
  end if;
  uname := lower(regexp_replace(base, '[^a-zA-Z0-9_]', '', 'g'));
  if uname = '' then
    uname := 'user';
  end if;
  uname := uname || '_' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);

  insert into public.profiles (id, display_name, username)
  values (new.id, base, uname);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.books enable row level security;
alter table public.friendships enable row level security;
alter table public.reading_groups enable row level security;
alter table public.reading_group_members enable row level security;

-- profiles
drop policy if exists "profiles_select_auth" on public.profiles;
create policy "profiles_select_auth"
  on public.profiles for select
  to authenticated
  using (true);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- books: eigenes Regal, Freunde oder gemeinsame Lesegruppe
drop policy if exists "books_select" on public.books;
create policy "books_select"
  on public.books for select
  to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and (
          (f.requester_id = auth.uid() and f.addressee_id = books.user_id)
          or (f.addressee_id = auth.uid() and f.requester_id = books.user_id)
        )
    )
    or exists (
      select 1
      from public.reading_group_members gm_self
      join public.reading_group_members gm_owner
        on gm_self.group_id = gm_owner.group_id
      where gm_self.user_id = auth.uid()
        and gm_owner.user_id = books.user_id
    )
  );

drop policy if exists "books_insert_own" on public.books;
create policy "books_insert_own"
  on public.books for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "books_update_own" on public.books;
create policy "books_update_own"
  on public.books for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "books_delete_own" on public.books;
create policy "books_delete_own"
  on public.books for delete
  to authenticated
  using (user_id = auth.uid());

-- friendships
drop policy if exists "friendships_select_participant" on public.friendships;
create policy "friendships_select_participant"
  on public.friendships for select
  to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());

drop policy if exists "friendships_insert_requester" on public.friendships;
create policy "friendships_insert_requester"
  on public.friendships for insert
  to authenticated
  with check (requester_id = auth.uid());

drop policy if exists "friendships_update_participant" on public.friendships;
create policy "friendships_update_participant"
  on public.friendships for update
  to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid())
  with check (requester_id = auth.uid() or addressee_id = auth.uid());

drop policy if exists "friendships_delete_participant" on public.friendships;
create policy "friendships_delete_participant"
  on public.friendships for delete
  to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- reading_groups
drop policy if exists "reading_groups_select" on public.reading_groups;
create policy "reading_groups_select"
  on public.reading_groups for select
  to authenticated
  using (true);

drop policy if exists "reading_groups_insert" on public.reading_groups;
create policy "reading_groups_insert"
  on public.reading_groups for insert
  to authenticated
  with check (created_by = auth.uid());

drop policy if exists "reading_groups_delete" on public.reading_groups;
create policy "reading_groups_delete"
  on public.reading_groups for delete
  to authenticated
  using (created_by = auth.uid());

drop policy if exists "reading_group_members_select" on public.reading_group_members;
create policy "reading_group_members_select"
  on public.reading_group_members for select
  to authenticated
  using (true);

drop policy if exists "reading_group_members_insert" on public.reading_group_members;
create policy "reading_group_members_insert"
  on public.reading_group_members for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "reading_group_members_delete" on public.reading_group_members;
create policy "reading_group_members_delete"
  on public.reading_group_members for delete
  to authenticated
  using (user_id = auth.uid());

-- Buch-Leihen (Freundesfreundeskreis)
create table if not exists public.book_loans (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books (id) on delete cascade,
  lender_id uuid not null references public.profiles (id) on delete cascade,
  borrower_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'returned')),
  created_at timestamptz default now(),
  returned_at timestamptz,
  check (lender_id <> borrower_id)
);

create unique index if not exists book_loans_one_active_per_book
  on public.book_loans (book_id)
  where status = 'active';

create index if not exists book_loans_lender_idx on public.book_loans (lender_id);
create index if not exists book_loans_borrower_idx on public.book_loans (borrower_id);

alter table public.book_loans enable row level security;

drop policy if exists "book_loans_select" on public.book_loans;
create policy "book_loans_select"
  on public.book_loans for select
  to authenticated
  using (
    lender_id = auth.uid()
    or borrower_id = auth.uid()
    or exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and (
          (f.requester_id = auth.uid() and f.addressee_id = book_loans.lender_id)
          or (f.addressee_id = auth.uid() and f.requester_id = book_loans.lender_id)
        )
    )
    or exists (
      select 1
      from public.reading_group_members gm_self
      join public.reading_group_members gm_lender on gm_self.group_id = gm_lender.group_id
      where gm_self.user_id = auth.uid()
        and gm_lender.user_id = book_loans.lender_id
    )
  );

drop policy if exists "book_loans_insert" on public.book_loans;
create policy "book_loans_insert"
  on public.book_loans for insert
  to authenticated
  with check (
    lender_id = auth.uid()
    and exists (select 1 from public.books b where b.id = book_id and b.user_id = auth.uid())
    and exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and (
          (f.requester_id = auth.uid() and f.addressee_id = borrower_id)
          or (f.addressee_id = auth.uid() and f.requester_id = borrower_id)
        )
    )
  );

drop policy if exists "book_loans_update" on public.book_loans;
create policy "book_loans_update"
  on public.book_loans for update
  to authenticated
  using (lender_id = auth.uid() or borrower_id = auth.uid())
  with check (lender_id = auth.uid() or borrower_id = auth.uid());
