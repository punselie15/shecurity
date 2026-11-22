# Circles v3: what to run (once)

1. **Database**: open Supabase, project "shecurity", SQL editor, paste all of `backend/circles-v3.sql`, Run.
   It is safe to run twice. It creates everyone's big circle, makes all existing links two-way,
   adds the SOS sharing column, the `sos-audio` storage bucket and its rules.
2. **Push functions** (so alerts go to exactly the right people): in Supabase, Edge Functions,
   open `notify`, replace its code with `backend/notify-function.ts`, Deploy. Do the same for
   `watch-alert` with `backend/watch-alert-function.ts` (keep "Verify JWT" off for watch-alert).
3. Merge the pull request. The website app updates right away; the store apps need a new build.

Do step 1 before merging: the new app falls back to the old way of reading circles until the SQL
is run, but small-circle picking, SOS sound and map highlights need it.
