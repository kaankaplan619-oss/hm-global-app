-- ============================================================
-- HM Global — outil interne : LOT 2 (planning)
-- Ajoute `importance` et `note` à la table tasks existante.
-- ------------------------------------------------------------
-- On NE crée PAS de colonne `fini` : "terminé" reste porté par la colonne
-- `status` (en cours | en attente | terminé) déjà en place, pour éviter
-- deux sources de vérité qui pourraient diverger.
--   - importance : pilote le tri des « 3 priorités »
--   - note       : texte long facultatif
-- Le RLS de `tasks` est déjà conforme au brief (lecture/écriture
-- « propriétaire ou admin ») — rien à changer de ce côté.
-- ============================================================

alter table public.tasks
  add column if not exists importance text not null default 'normale'
    check (importance in ('faible','normale','haute','urgente')),
  add column if not exists note text;
