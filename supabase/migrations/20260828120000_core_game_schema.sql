-- Core game schema: Player, Computer, Hardware, Software, Process, Connection,
-- Bank Account/Dinheiro, Wallet/HackerCoin, Log.
--
-- Resolves issue #4 (child of map issue #2). See CONTEXT.md for domain vocabulary
-- and docs/adr/0001-0006 for the architectural decisions this schema follows.
--
-- Scope boundary: this migration ships the full table shapes, RLS, and the
-- generic Process start/resolve RPC skeleton. It deliberately does NOT
-- implement game-balance specifics owned by later map tickets:
--   - Hardware/Software catalog content                -> #5, #6
--   - Target discovery                                  -> #7
--   - Hack success/failure resolution                   -> #8
--   - Currency traceability semantics, steal amounts     -> #9
--   - Process-completion notification mechanism          -> #10
--   - Player/Computer provisioning on signup             -> #11
-- Those extension points are marked with TODO(#n) comments below.

create extension if not exists pgcrypto;

-- ============================================================================
-- Enums
-- ============================================================================

create type public.hardware_slot as enum ('cpu', 'ram', 'hd', 'net');
create type public.currency_type as enum ('dinheiro', 'hackercoin');
create type public.process_kind as enum ('hack', 'steal', 'log_delete');

-- ============================================================================
-- Identity
-- ============================================================================

-- A Player IS the auth account: no identity independent of auth.users.
create table public.players (
  id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

-- 1:1 with Player. IP address is assigned once at provisioning time (#11).
create table public.computers (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null unique references public.players (id) on delete cascade,
  ip_address inet not null unique,
  created_at timestamptz not null default now()
);

-- ============================================================================
-- Hardware & Software: catalog (static definitions) + instance (ownership/install)
-- ============================================================================

-- Content populated by ticket #5.
create table public.hardware_catalog (
  id uuid primary key default gen_random_uuid(),
  slot public.hardware_slot not null,
  name text not null unique,
  created_at timestamptz not null default now()
);

-- Content populated by ticket #6.
create table public.software_catalog (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

-- Owned Hardware units (inventory; may include spares not currently installed).
create table public.player_hardware (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players (id) on delete cascade,
  hardware_catalog_id uuid not null references public.hardware_catalog (id),
  acquired_at timestamptz not null default now()
);

-- Owned Software units (inventory; may include copies not currently installed).
create table public.player_software (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players (id) on delete cascade,
  software_catalog_id uuid not null references public.software_catalog (id),
  acquired_at timestamptz not null default now()
);

-- Which owned Hardware unit is installed in which Slot on a Computer.
-- At most one unit per (computer_id, slot).
create table public.computer_hardware (
  computer_id uuid not null references public.computers (id) on delete cascade,
  slot public.hardware_slot not null,
  player_hardware_id uuid not null unique references public.player_hardware (id) on delete cascade,
  installed_at timestamptz not null default now(),
  primary key (computer_id, slot)
);

-- Which owned Software units are installed/active on a Computer.
create table public.computer_software (
  computer_id uuid not null references public.computers (id) on delete cascade,
  player_software_id uuid not null unique references public.player_software (id) on delete cascade,
  installed_at timestamptz not null default now(),
  primary key (computer_id, player_software_id)
);

-- Structural invariants: an installed unit must match its declared slot and
-- must be owned by the same Player who owns the Computer it's installed on.
create or replace function public.check_computer_hardware()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hw_slot public.hardware_slot;
  v_hw_player_id uuid;
  v_computer_player_id uuid;
begin
  select hc.slot, ph.player_id into v_hw_slot, v_hw_player_id
  from public.player_hardware ph
  join public.hardware_catalog hc on hc.id = ph.hardware_catalog_id
  where ph.id = new.player_hardware_id;

  select player_id into v_computer_player_id
  from public.computers where id = new.computer_id;

  if v_hw_slot is distinct from new.slot then
    raise exception 'hardware unit does not match slot %', new.slot;
  end if;

  if v_hw_player_id is distinct from v_computer_player_id then
    raise exception 'cannot install hardware you do not own';
  end if;

  return new;
end;
$$;

create trigger trg_check_computer_hardware
before insert or update on public.computer_hardware
for each row execute function public.check_computer_hardware();

create or replace function public.check_computer_software()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sw_player_id uuid;
  v_computer_player_id uuid;
begin
  select player_id into v_sw_player_id
  from public.player_software where id = new.player_software_id;

  select player_id into v_computer_player_id
  from public.computers where id = new.computer_id;

  if v_sw_player_id is distinct from v_computer_player_id then
    raise exception 'cannot install software you do not own';
  end if;

  return new;
end;
$$;

create trigger trg_check_computer_software
before insert or update on public.computer_software
for each row execute function public.check_computer_software();

-- ============================================================================
-- Currency: Dinheiro (traceable, Bank Account) / HackerCoin (untraceable, Wallet)
-- ============================================================================

-- 1:1 with Player.
create table public.bank_accounts (
  player_id uuid primary key references public.players (id) on delete cascade,
  balance bigint not null default 0 check (balance >= 0)
);

-- 1:1 with Player.
create table public.wallets (
  player_id uuid primary key references public.players (id) on delete cascade,
  balance bigint not null default 0 check (balance >= 0)
);

-- Log entry. related_process_id FK added below, after processes exists
-- (logs and processes reference each other).
create table public.logs (
  id uuid primary key default gen_random_uuid(),
  computer_id uuid not null references public.computers (id) on delete cascade,
  actor_player_id uuid references public.players (id),
  action text not null,
  occurred_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Process. Single generic table for every async timed action (ADR-0005).
-- Resolved lazily: nothing writes when ends_at elapses, only when
-- resolve_process() is next called against the row (ADR-0002).
create table public.processes (
  id uuid primary key default gen_random_uuid(),
  kind public.process_kind not null,
  computer_id uuid not null references public.computers (id) on delete cascade,
  target_computer_id uuid references public.computers (id),
  target_log_id uuid references public.logs (id),
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.logs
  add column related_process_id uuid references public.processes (id);

-- Movements ledger for both currencies (hybrid: mutable balance + audit trail).
create table public.currency_movements (
  id uuid primary key default gen_random_uuid(),
  currency public.currency_type not null,
  player_id uuid not null references public.players (id),
  amount bigint not null,
  related_process_id uuid references public.processes (id),
  counterparty_player_id uuid references public.players (id),
  created_at timestamptz not null default now()
);

-- Connection: own table (ADR-0005), created on successful Hack resolution.
-- Many-to-many concurrency allowed; only one *active* connection per
-- (attacker, target) pair at a time.
create table public.connections (
  id uuid primary key default gen_random_uuid(),
  attacker_computer_id uuid not null references public.computers (id) on delete cascade,
  target_computer_id uuid not null references public.computers (id) on delete cascade,
  established_at timestamptz not null default now(),
  ended_at timestamptz
);

create unique index connections_active_pair_idx
  on public.connections (attacker_computer_id, target_computer_id)
  where ended_at is null;

-- ============================================================================
-- RLS helper functions (SECURITY DEFINER to avoid recursive-policy issues;
-- search_path pinned per Supabase RLS guidance).
-- ============================================================================

create or replace function public.is_own_computer(p_computer_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.computers c
    where c.id = p_computer_id and c.player_id = (select auth.uid())
  );
$$;

-- Reusable by tickets #7/#8 when they build cross-Player visibility policies.
create or replace function public.has_active_connection(p_attacker_computer_id uuid, p_target_computer_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.connections conn
    where conn.attacker_computer_id = p_attacker_computer_id
      and conn.target_computer_id = p_target_computer_id
      and conn.ended_at is null
  );
$$;

-- ============================================================================
-- RLS: self-owner baseline on every table (cross-Player visibility for
-- target-discovery / hack gameplay is deferred to #7/#8, per ticket #4's
-- agreed scope).
-- ============================================================================

alter table public.players enable row level security;
alter table public.computers enable row level security;
alter table public.hardware_catalog enable row level security;
alter table public.software_catalog enable row level security;
alter table public.player_hardware enable row level security;
alter table public.player_software enable row level security;
alter table public.computer_hardware enable row level security;
alter table public.computer_software enable row level security;
alter table public.bank_accounts enable row level security;
alter table public.wallets enable row level security;
alter table public.currency_movements enable row level security;
alter table public.logs enable row level security;
alter table public.processes enable row level security;
alter table public.connections enable row level security;

create policy "players read own row" on public.players
  for select to authenticated
  using (id = (select auth.uid()));

create policy "players read own computer" on public.computers
  for select to authenticated
  using (player_id = (select auth.uid()));

create policy "catalog readable by any authenticated player" on public.hardware_catalog
  for select to authenticated
  using (true);

create policy "catalog readable by any authenticated player" on public.software_catalog
  for select to authenticated
  using (true);

create policy "players read own hardware inventory" on public.player_hardware
  for select to authenticated
  using (player_id = (select auth.uid()));

create policy "players read own software inventory" on public.player_software
  for select to authenticated
  using (player_id = (select auth.uid()));

create policy "players read own installed hardware" on public.computer_hardware
  for select to authenticated
  using (public.is_own_computer(computer_id));

create policy "players read own installed software" on public.computer_software
  for select to authenticated
  using (public.is_own_computer(computer_id));

create policy "players read own bank account" on public.bank_accounts
  for select to authenticated
  using (player_id = (select auth.uid()));

create policy "players read own wallet" on public.wallets
  for select to authenticated
  using (player_id = (select auth.uid()));

create policy "players read own currency movements" on public.currency_movements
  for select to authenticated
  using (player_id = (select auth.uid()));

-- A Log is visible to the Computer it's on (self-owner from that Player's
-- side), never once deleted_at is set (ADR-0006).
create policy "players read own computer's logs" on public.logs
  for select to authenticated
  using (public.is_own_computer(computer_id) and deleted_at is null);

-- Each party to a Process can see it: the actor (their own outgoing
-- Process) and the target (an incoming Process against their own
-- Computer) -- both are "my own Computer's data", not cross-Player.
create policy "players read processes touching their computer" on public.processes
  for select to authenticated
  using (public.is_own_computer(computer_id) or public.is_own_computer(target_computer_id));

create policy "players read connections touching their computer" on public.connections
  for select to authenticated
  using (public.is_own_computer(attacker_computer_id) or public.is_own_computer(target_computer_id));

-- ============================================================================
-- Authoritative RPCs (ADR-0004: Postgres SECURITY DEFINER only, no Edge
-- Functions). Kind-specific game rules not yet decided by the map are
-- clearly marked as placeholders below.
-- ============================================================================

create or replace function public.start_process(
  p_kind public.process_kind,
  p_computer_id uuid,
  p_target_computer_id uuid default null,
  p_target_log_id uuid default null
)
returns public.processes
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_duration_seconds integer;
  v_log_computer_id uuid;
  v_log_actor_id uuid;
  v_process public.processes;
begin
  if not public.is_own_computer(p_computer_id) then
    raise exception 'not your computer';
  end if;

  if p_kind = 'hack' then
    if p_target_computer_id is null then
      raise exception 'hack requires a target computer';
    end if;
    if p_target_computer_id = p_computer_id then
      raise exception 'cannot hack your own computer';
    end if;
    -- TODO(#7): target must actually be discoverable/reachable; not enforced yet.

  elsif p_kind = 'steal' then
    if p_target_computer_id is null or not public.has_active_connection(p_computer_id, p_target_computer_id) then
      raise exception 'steal requires an active connection to the target';
    end if;

  elsif p_kind = 'log_delete' then
    if p_target_log_id is null then
      raise exception 'log_delete requires a target log';
    end if;

    select l.computer_id, l.actor_player_id into v_log_computer_id, v_log_actor_id
    from public.logs l
    where l.id = p_target_log_id and l.deleted_at is null;

    if v_log_computer_id is null then
      raise exception 'log not found';
    end if;
    if v_log_actor_id is distinct from (select auth.uid()) then
      raise exception 'you did not cause this log entry';
    end if;
    if not public.has_active_connection(p_computer_id, v_log_computer_id) then
      raise exception 'log_delete requires an active connection to the log''s computer';
    end if;

    p_target_computer_id := v_log_computer_id;
  end if;

  -- TODO(#5, #6): duration must be derived from the actor Computer's
  -- installed Hardware/Software once those catalogs carry real stats.
  -- Placeholder fixed durations for now.
  v_duration_seconds := case p_kind
    when 'hack' then 120
    when 'steal' then 30
    when 'log_delete' then 45
  end;

  insert into public.processes (kind, computer_id, target_computer_id, target_log_id, starts_at, ends_at)
  values (p_kind, p_computer_id, p_target_computer_id, p_target_log_id, now(), now() + make_interval(secs => v_duration_seconds))
  returning * into v_process;

  return v_process;
end;
$$;

create or replace function public.resolve_process(p_process_id uuid)
returns public.processes
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_process public.processes;
  v_target_player_id uuid;
  v_actor_player_id uuid;
begin
  select * into v_process from public.processes where id = p_process_id for update;

  if v_process.id is null then
    raise exception 'process not found';
  end if;

  if not (public.is_own_computer(v_process.computer_id) or public.is_own_computer(v_process.target_computer_id)) then
    raise exception 'not your process';
  end if;

  if v_process.resolved_at is not null then
    return v_process; -- idempotent: already resolved
  end if;

  if v_process.ends_at > now() then
    return v_process; -- not finished yet
  end if;

  if v_process.kind = 'hack' then
    -- TODO(#8): success/failure resolution (target defenses, probability)
    -- belongs to "Fluxo de hackeamento: resolução de sucesso/falha e roubo".
    -- Placeholder: every hack that runs to completion succeeds.
    insert into public.connections (attacker_computer_id, target_computer_id)
    values (v_process.computer_id, v_process.target_computer_id)
    on conflict do nothing;

  elsif v_process.kind = 'steal' then
    -- TODO(#9): stolen amount and Dinheiro/HackerCoin traceability semantics
    -- belong to "Semântica de rastreabilidade das moedas e mecânica de Log".
    -- Placeholder: steal a fixed 100 Dinheiro from the target's Bank Account.
    select player_id into v_target_player_id from public.computers where id = v_process.target_computer_id;
    select player_id into v_actor_player_id from public.computers where id = v_process.computer_id;

    update public.bank_accounts set balance = balance - 100 where player_id = v_target_player_id;
    update public.bank_accounts set balance = balance + 100 where player_id = v_actor_player_id;

    insert into public.currency_movements (currency, player_id, amount, related_process_id, counterparty_player_id)
    values
      ('dinheiro', v_target_player_id, -100, v_process.id, v_actor_player_id),
      ('dinheiro', v_actor_player_id, 100, v_process.id, v_target_player_id);

    -- Dinheiro movements produce a Log the Target can see (CONTEXT.md).
    insert into public.logs (computer_id, actor_player_id, action, related_process_id)
    values (v_process.target_computer_id, v_actor_player_id, 'dinheiro_stolen', v_process.id);

  elsif v_process.kind = 'log_delete' then
    update public.logs set deleted_at = now() where id = v_process.target_log_id;
  end if;

  update public.processes set resolved_at = now() where id = v_process.id
  returning * into v_process;

  -- TODO(#10): trigger a Realtime notification on resolution; this RPC only
  -- performs the authoritative write, per "Conclusão de Processo e mecanismo
  -- de notificação Realtime".
  return v_process;
end;
$$;

create or replace function public.disconnect(p_connection_id uuid)
returns public.connections
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_connection public.connections;
begin
  select * into v_connection from public.connections where id = p_connection_id for update;

  if v_connection.id is null then
    raise exception 'connection not found';
  end if;

  if not public.is_own_computer(v_connection.attacker_computer_id) then
    raise exception 'only the attacker can disconnect';
  end if;

  if v_connection.ended_at is not null then
    return v_connection; -- idempotent
  end if;

  update public.connections set ended_at = now() where id = p_connection_id
  returning * into v_connection;

  return v_connection;
end;
$$;

-- ============================================================================
-- Grants: table-level SELECT for the self-owner RLS above, EXECUTE on the
-- authoritative RPCs and RLS helper functions. No direct table-level
-- INSERT/UPDATE/DELETE grants to `authenticated` -- all writes flow through
-- the SECURITY DEFINER RPCs above.
-- ============================================================================

grant usage on schema public to authenticated;

grant select on
  public.players,
  public.computers,
  public.hardware_catalog,
  public.software_catalog,
  public.player_hardware,
  public.player_software,
  public.computer_hardware,
  public.computer_software,
  public.bank_accounts,
  public.wallets,
  public.currency_movements,
  public.logs,
  public.processes,
  public.connections
to authenticated;

grant execute on function public.is_own_computer(uuid) to authenticated;
grant execute on function public.has_active_connection(uuid, uuid) to authenticated;
grant execute on function public.start_process(public.process_kind, uuid, uuid, uuid) to authenticated;
grant execute on function public.resolve_process(uuid) to authenticated;
grant execute on function public.disconnect(uuid) to authenticated;
