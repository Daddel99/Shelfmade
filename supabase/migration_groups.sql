-- Lese-/Buchgruppen: einmal im SQL Editor ausführen (nach bestehendem schema / migration_cover_rating)

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

alter table public.reading_groups enable row level security;
alter table public.reading_group_members enable row level security;

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

-- Bücher auch lesbar, wenn dieselbe reading_group
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
