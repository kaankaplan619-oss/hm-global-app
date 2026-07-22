# Décisions produit — Outil interne HM Global

Ce fichier consigne les décisions prises, pour ne pas les reperdre ni les re-débattre.

## Sécurité / architecture
- **Pas de réécriture Next.js** pour l'instant : on consolide l'app HTML/JS existante.
  (À rediscuter uniquement si un chiffrage prouve que consolider coûte plus cher.)
- **Un seul fichier `index.html` sécurisé** à la racine. Les anciens (`index_2/3`,
  ancienne `index.html`) ont été supprimés car non sécurisés (mots de passe en clair,
  ancien projet Supabase mort).
- **Projet Supabase : `hmglobal-interne-v2`** (Paris). L'ancien (`nvufbzepicxubxdxutph`)
  est mort et doit être ignoré/supprimé.
- Règle permanente : **RLS activé sur toute nouvelle table**, lecture/écriture
  « propriétaire ou admin », `is_admin()` en schéma `private`, tout affichage échappé.

## Confidentialité
- **L'admin peut lire les notes vocales des collaborateurs** (police `notes_admin_read`).
  Décision validée (« l'admin voit tout »).
  ⚠️ **À annoncer à l'équipe au moment du déploiement** : personne ne doit dicter une
  note en la croyant privée. C'est une question de confiance.

## Planning (LOT 2)
- **Périmètre v1 réduit** : **vue semaine + tâches + 3 priorités**. C'est tout.
- **Ajouté par incréments ensuite** : fournisseurs, boîte « à trier », pastilles d'outils.
- **Points / niveaux / série : EN DERNIER**, après que le planning de base soit
  réellement utilisé au quotidien. Sans usage quotidien, les points ne servent à rien.
- **Exclus** (ne pas construire) : glisser-déposer, vue mois, tâches récurrentes,
  notifications mail/push, badges/trophées/avatars, emojis à la place des pastilles.

## Ordre de travail
- **LOT 0** sécurité → **LOT 1** retours utilisateur (déjà fait) → **LOT 2** planning
  → **LOT 3** copilote d'appel (plus tard, sur décision de Kaan).
- Un lot à la fois, validé avant le suivant. **Rien en ligne sans accord explicite ;
  préavis avant chaque push.**
