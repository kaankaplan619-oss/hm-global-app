// Crée un compte Supabase Auth pour chaque ligne de public.users, avec le
// même e-mail et le même mot de passe : chacun se reconnecte sans rien changer.
// Rejouable : les comptes déjà présents sont ignorés. N'affiche aucun mot de passe.
//
// À lancer UNE fois, en local, après l'étape 1 et avant l'étape 2 (voir SECURITE.md) :
//   cd scripts && npm ci
//   SUPABASE_URL=https://<projet>.supabase.co SUPABASE_SECRET_KEY=<clé secrète> node migrate-users-to-auth.mjs --dry-run
//   SUPABASE_URL=https://<projet>.supabase.co SUPABASE_SECRET_KEY=<clé secrète> node migrate-users-to-auth.mjs
//
// La clé secrète (sb_secret_… ou ancienne clé service_role) ne doit jamais
// apparaître dans une page HTML ni être commitée.
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SECRET_KEY;
const dryRun = process.argv.includes('--dry-run');
if (!url || !key) {
  console.error('Définissez SUPABASE_URL et SUPABASE_SECRET_KEY.');
  process.exit(1);
}

const sb = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });

const { data: users, error } = await sb.from('users').select('id, email, name, password');
if (error) {
  console.error('Lecture de public.users impossible :', error.message);
  process.exit(1);
}

const existing = new Set();
for (let page = 1; ; page++) {
  const { data, error } = await sb.auth.admin.listUsers({ page, perPage: 1000 });
  if (error) {
    console.error('Lecture des comptes Supabase Auth impossible :', error.message);
    process.exit(1);
  }
  for (const u of data.users) if (u.email) existing.add(u.email.toLowerCase());
  if (data.users.length < 1000) break;
}

let failed = 0;
for (const u of users) {
  const email = (u.email || '').trim().toLowerCase();
  if (!email) {
    console.error(`! id ${u.id} : pas d'e-mail, compte à créer à la main`);
    failed++;
  } else if (existing.has(email)) {
    console.log(`= ${email} : compte déjà présent`);
  } else if (dryRun) {
    console.log(`+ ${email} : serait créé`);
  } else {
    const { error } = await sb.auth.admin.createUser({
      email,
      password: u.password,
      email_confirm: true,
      user_metadata: { name: u.name },
    });
    if (error) {
      console.error(`! ${email} : ${error.message}`);
      failed++;
    } else {
      console.log(`+ ${email} : compte créé`);
    }
  }
}

console.log(failed ? `${failed} compte(s) en erreur.` : 'Terminé.');
process.exit(failed ? 1 : 0);
