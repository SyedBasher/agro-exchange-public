-- Agro-Exchange phone-auth profile bootstrap.
-- Applied to the live Supabase project in v0.7.
-- New authenticated users enter the pilot as farmers. Buyer/admin roles are assigned separately.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles(
    auth_user_id,
    role,
    display_name,
    phone,
    preferred_language,
    verified
  ) values (
    new.id,
    'farmer'::user_role,
    coalesce(nullif(new.raw_user_meta_data->>'display_name',''), 'Farmer'),
    new.phone,
    case when new.raw_user_meta_data->>'preferred_language' = 'en' then 'en' else 'bn' end,
    false
  )
  on conflict (auth_user_id) do update
    set phone = excluded.phone,
        updated_at = now();
  return new;
end;
$$;

revoke all on function public.handle_new_auth_user() from public, anon, authenticated;
grant execute on function public.handle_new_auth_user() to supabase_auth_admin;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();
