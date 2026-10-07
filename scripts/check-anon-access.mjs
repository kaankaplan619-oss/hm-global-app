// Vérifie ce que permet la clé publique (publishable/anon) seule, sans compte connecté.
// Attendu après l'étape 2 : toutes les lectures et écritures sont refusées.
//
//   cd scripts && npm ci && node check-anon-access.mjs
//   (SUPABASE_URL / SUPABASE_ANON_KEY pour cibler un autre projet)
//
// Les écritures testées visent une valeur témoin qui ne correspond à aucune
// ligne ; si un insert passe malgré tout, la ligne témoin est supprimée.
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL || 'https://nvufbzepicxubxdxutph.supabase.co';
const key = process.env.SUPABASE_ANON_KEY || 'sb_publishable_aN_ivcfpLzujhkoblpNB0w_GapMeD0V';
const sb = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });

const MARK = `__test_acces_anon_${Date.now()}__`;
// Colonne texte de chaque table utilisée pour cibler la valeur témoin.
const TABLES = { users: 'email', profiles: 'email', clients: 'name', tasks: 'title', notes: 'fr' };

let open = 0;
const report = (label, ok, detail) => {
  if (!ok) open++;
  console.log(`${ok ? 'OK    ' : 'OUVERT'} ${label} — ${detail}`);
};
// 42501 = droit ou politique RLS refusé ; PGRST205 = table absente de l'API.
// Toute autre erreur (contrainte NOT NULL…) signifie que le droit a été accordé.
const check = (label, { error }) => {
  const denied = error && (error.code === '42501' || error.code === 'PGRST205');
  report(label, denied, error ? `${denied ? 'refusé' : 'à vérifier'} (${error.code}: ${error.message})` : 'autorisé');
  return error;
};

for (const [table, col] of Object.entries(TABLES)) {
  const r = await sb.from(table).select('*').limit(5);
  if (r.error) check(`lecture ${table}`, r);
  else report(`lecture ${table}`, r.data.length === 0, `${r.data.length} ligne(s) visible(s)`);

  check(`modification ${table}`, await sb.from(table).update({ [col]: MARK }).eq(col, MARK));
  check(`suppression ${table}`, await sb.from(table).delete().eq(col, MARK));

  if (table === 'users' || table === 'profiles') continue;
  if (!check(`ajout ${table}`, await sb.from(table).insert({ [col]: MARK }))) {
    await sb.from(table).delete().eq(col, MARK);
  }
}

console.log(open ? `\n${open} accès encore ouvert(s) avec la seule clé publique.` : '\nAucun accès avec la seule clé publique.');
process.exit(open ? 1 : 0);
