# Sécurisation de l'espace interne (Supabase Auth + RLS)

## Le problème corrigé

Les pages se connectaient en lisant la table `users` avec la clé publique
embarquée dans le HTML. Pour que ça marche, cette table devait être lisible par
n'importe qui : toute personne ouvrant la page pouvait récupérer les e-mails et
les mots de passe (en clair). Elle pouvait aussi écrire et supprimer dans
`clients`, `tasks` et `notes` sans être connectée.

## Ce qui change

| Avant | Après |
| --- | --- |
| `select * from users where email = … and password = …` | `sb.auth.signInWithPassword()` (Supabase Auth, mots de passe hachés en bcrypt) |
| Rôle lu dans `users.role` | Rôle lu dans `profiles.role`, table liée à `auth.users` |
| Aucune règle côté serveur | RLS sur `users`, `profiles`, `clients`, `tasks`, `notes` |
| Mots de passe en clair dans `users.password` | Colonne supprimée (étape 3) |
| Données injectées telles quelles via `innerHTML` | Tout est échappé avec `esc()` |

Règles appliquées par la base, pas par la page :

- **Clé publique seule** (pas de session) : aucun accès à aucune table.
- **Collab** : voit et modifie uniquement ses tâches et ses notes, voit son
  profil, lit la liste des clients (pour créer une tâche).
- **Admin** : voit toutes les tâches, notes et profils ; seul à pouvoir
  ajouter, modifier ou supprimer un client.
- **Compte Auth sans profil** (ex. inscription non prévue) : aucun accès.
- `users` n'est plus accessible via l'API, même connecté.

Les quatre pages (`index.html`, `index_2.html`, `index_3.html`, `index_4.html`)
ont été mises à jour. La session est conservée au rechargement de la page.

## Mise en production (à faire par le propriétaire, dans cet ordre)

Rien n'a été appliqué au projet Supabase ni déployé.

> Le dépôt est relié à Vercel : fusionner cette branche dans `main` déploie les
> nouvelles pages en production. **Ne pas fusionner avant l'étape 2** (les
> nouvelles pages ne peuvent se connecter qu'une fois les profils créés), puis
> fusionner juste après.

0. **Sauvegarde** : Database > Backups dans le tableau de bord Supabase (ou
   `pg_dump`).
1. **Désactiver les inscriptions publiques** : Authentication > Sign In /
   Providers > désactiver *Allow new users to sign up*. Laisser le fournisseur
   *Email* activé. Les comptes sont créés uniquement par l'admin.
2. **Étape 1** : dans le SQL Editor, exécuter
   `supabase/migrations/20261007120000_profiles.sql`. Sans effet sur les pages
   actuelles.
3. **Créer les comptes Supabase Auth**, au choix :
   - *Script (recommandé, garde les mots de passe actuels)* : récupérer la clé
     secrète (Project Settings > API Keys > Secret keys, `sb_secret_…`) puis :
     ```sh
     cd scripts && npm ci
     SUPABASE_URL=https://nvufbzepicxubxdxutph.supabase.co SUPABASE_SECRET_KEY=sb_secret_… node migrate-users-to-auth.mjs --dry-run
     SUPABASE_URL=https://nvufbzepicxubxdxutph.supabase.co SUPABASE_SECRET_KEY=sb_secret_… node migrate-users-to-auth.mjs
     ```
     Le script est rejouable. Il refuse un mot de passe trop court pour Supabase
     (moins de 6 caractères) : créer ce compte à la main.
   - *À la main* : Authentication > Users > Add user > Create new user, même
     e-mail que dans `users`, cocher *Auto Confirm User*.
4. **Étape 2 + déploiement** : exécuter
   `supabase/migrations/20261007120100_link_profiles_enable_rls.sql` (le fichier
   entier, d'un bloc), **puis déployer aussitôt les nouvelles pages** (fusion
   dans `main`, Vercel déploie) : à partir de cette étape, les anciennes pages
   ne peuvent plus se connecter.
   Le script vérifie d'abord que chaque ligne de `users` a un compte Auth, qu'il
   n'y a pas d'e-mail en double ni de tâche/note orpheline ; sinon il s'arrête
   sans rien modifier. Il supprime aussi les anciennes politiques RLS de ces
   tables (une politique du type « allow all » annulerait les nouvelles).
5. **Vérifier** :
   - se connecter avec le compte admin et avec chaque collab ;
   - `cd scripts && node check-anon-access.mjs` doit finir par
     *Aucun accès avec la seule clé publique.*
6. **Étape 3** : une fois tout le monde reconnecté, exécuter
   `supabase/migrations/20261007120200_drop_plaintext_passwords.sql`.
7. **Changer les mots de passe** : ils ont été lisibles publiquement, il faut les
   considérer comme compromis (Authentication > Users > *Send password
   recovery*, ou nouveau mot de passe défini par l'admin).

En cas de problème après l'étape 2 : restaurer la sauvegarde de l'étape 0 et
remettre les anciennes pages.

## Ajouter un collaborateur plus tard

1. Authentication > Users > Add user (e-mail + mot de passe, *Auto Confirm User*).
2. SQL Editor :
   ```sql
   insert into public.profiles (id, email, name, role)
   select id, email, 'Prénom', 'collab' from auth.users where email = 'prenom@hmglobal.fr';
   ```
   (`'admin'` à la place de `'collab'` pour un administrateur.)

## Hypothèses et tests

Le schéma du projet `nvufbzepicxubxdxutph` n'était pas accessible pendant ce
travail : il a été déduit du code (`users(id, email, password, name, role)`,
`clients`, `tasks(user_id, client_id, …)`, `notes(user_id, …)`). L'étape 2
fonctionne que `users.id` soit un `bigint` ou un `uuid`.

Testé en local sur Postgres 16 + Supabase Auth (GoTrue) + PostgREST, avec des
ids `bigint` puis `uuid`, avec et sans politiques « allow all » préexistantes :

- avant : la clé publique lit `users.password` (faille reproduite) ;
- après : 18/18 lectures et écritures refusées avec la clé publique seule ;
- connexion admin et collab, reprise de session, déconnexion, mauvais mot de
  passe, ajout de tâche par un collab, ajout et suppression de client par
  l'admin, refus des mêmes actions pour un collab : OK sur les quatre pages ;
- des noms de clients, titres de tâches et notes contenant du HTML/JS
  s'affichent comme du texte, sans exécution.
