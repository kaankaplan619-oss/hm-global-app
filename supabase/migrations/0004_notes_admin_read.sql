-- ============================================================
-- HM Global — outil interne : l'admin peut lire les notes
-- ------------------------------------------------------------
-- Décision produit : le Directeur (admin) doit pouvoir consulter les
-- notes vocales de ses collaborateurs depuis leur fiche.
--
-- Politique SELECT supplémentaire, permissive (combinée en OR avec la
-- règle "propriétaire" notes_all). L'écriture et la suppression restent
-- réservées à l'auteur de la note.
-- ============================================================

create policy "notes_admin_read" on public.notes
  for select using (private.is_admin());
