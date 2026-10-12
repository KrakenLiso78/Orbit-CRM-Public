-- Bounded owner read used to prepare a versioned reassessment without duplicating source evidence.

create function public.list_open_job_postings_for_reassessment(p_limit integer default 500)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_owner_id uuid := (select auth.uid());
begin
  if v_owner_id is null then
    raise exception 'authentication is required' using errcode = '42501';
  end if;
  if p_limit is null or p_limit not between 1 and 1000 then
    raise exception 'limit must be between 1 and 1000' using errcode = '22023';
  end if;

  return jsonb_build_object('roles', coalesce((
    select jsonb_agg(jsonb_build_object(
      'job_posting_id', j.id,
      'company_name', c.name,
      'title', j.title,
      'location', j.location,
      'work_arrangement', j.work_arrangement,
      'source_url', j.source_url,
      'job_description_snapshot_id', s.id,
      'description_summary', s.content_text,
      'score', a.score,
      'confidence', a.confidence,
      'rationale', a.rationale,
      'strengths', a.strengths,
      'gaps', a.gaps,
      'constraints', a.constraints,
      'profile_label', p.version_label,
      'rubric_label', r.version_label,
      'assessed_at', a.assessed_at
    ) order by c.name, j.title)
    from (
      select * from public.job_postings
      where owner_id = v_owner_id and status = 'open'
        and not exists (
          select 1 from public.job_dismissals d
          where d.owner_id = public.job_postings.owner_id
            and d.job_posting_id = public.job_postings.id
        )
      order by id
      limit p_limit
    ) j
    join public.companies c on c.owner_id = j.owner_id and c.id = j.company_id
    join lateral (
      select fa.* from public.fit_assessments fa
      where fa.owner_id = j.owner_id and fa.job_posting_id = j.id
      order by fa.assessed_at desc, fa.id desc limit 1
    ) a on true
    join public.candidate_profile_versions p on p.owner_id = a.owner_id and p.id = a.candidate_profile_version_id
    join public.scoring_rubric_versions r on r.owner_id = a.owner_id and r.id = a.scoring_rubric_version_id
    join public.job_description_snapshots s
      on s.owner_id = a.owner_id and s.id = a.job_description_snapshot_id
  ), '[]'::jsonb));
end;
$$;

revoke all on function public.list_open_job_postings_for_reassessment(integer) from public, anon;
grant execute on function public.list_open_job_postings_for_reassessment(integer) to authenticated;

comment on function public.list_open_job_postings_for_reassessment(integer) is
  'Owner-scoped current open, non-dismissed postings with their latest assessment and retained evidence snapshot.';
