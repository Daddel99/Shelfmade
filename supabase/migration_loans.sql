-- Buch-Leihen zwischen Freunden (nach Freundschaft + Profilen)

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
