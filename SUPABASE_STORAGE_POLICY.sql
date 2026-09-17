-- Safe to run more than once in Supabase SQL Editor.
do $$
begin
	if not exists (
		select 1 from pg_policies
		where schemaname = 'storage'
			and tablename = 'objects'
			and policyname = 'Allow audio downloads'
	) then
		create policy "Allow audio downloads"
		on storage.objects
		for select
		to anon, authenticated
		using (bucket_id = 'audios');
	end if;

	if not exists (
		select 1 from pg_policies
		where schemaname = 'storage'
			and tablename = 'objects'
			and policyname = 'Allow audio uploads'
	) then
		create policy "Allow audio uploads"
		on storage.objects
		for insert
		to anon, authenticated
		with check (bucket_id = 'audios');
	end if;
end $$;
