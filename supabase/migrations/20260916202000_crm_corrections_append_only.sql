-- Correction history is evidence. Neither a client nor a future business RPC
-- may revise or erase an already recorded amendment.
create trigger crm_corrections_append_only_update
before update on public.crm_corrections
for each row execute function private.prevent_row_update();

create trigger crm_corrections_append_only_delete
before delete on public.crm_corrections
for each row execute function private.prevent_row_update();
