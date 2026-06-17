-- ~/mSM/templates/askem/template.lua
--
-- Template "askem" : valeurs par défaut appliquées à tous les decks .md
-- qui ne précisent pas autre chose. Toute clé écrite dans le frontmatter
-- d'un .md surcharge la valeur correspondante ici.
--
-- Pour désactiver complètement le template sur un deck, écris dans le .md :
--     template: none
--
-- Pour basculer sur un autre template, crée un dossier
--     ~/mSM/templates/<nom>/template.lua
-- et écris dans le .md :
--     template: <nom>
--
-- Tous les paramètres ci-dessous sont optionnels : retire ceux que tu
-- ne veux pas imposer.

return {
  -- ============ PALETTE ============
  -- Couleurs hex (#rrggbb). Triade cool : mint + sky + lavande sur fond bleu nuit.
  -- Voir aussi les 5 presets natifs de mSM : dark, light, cream, slate, solar
  -- (cf. README dans ~/mSM/).
  background = "#0d1421",   -- bleu nuit profond
  color      = "#e8eef7",   -- corps de texte (presque blanc)
  accent     = "#5eead4",   -- titres `#` : mint / teal moderne
  h2         = "#7dd3fc",   -- titres `##` : sky blue
  h3         = "#c4b5fd",   -- titres `###` : lavande
  muted      = "#94a3b8",   -- citations, index
  note       = "#cbd5e1",   -- paragraphes "-> note"

  -- ============ TYPOGRAPHIE ============
  -- Tailles en pixels (en chaîne, mSM convertit). Pour utiliser une police
  -- custom : `font = "/chemin/absolu/MaPolice.ttf"` ou relatif au dossier
  -- du template ("ma-police.ttf"). mSM cherche automatiquement les
  -- variantes Bold / Italic / BoldItalic à côté.
  fontSize   = "32",        -- corps de texte
  titleSize  = "76",        -- titres `#`
  -- codeSize   = "24",     -- blocs de code (par défaut 24)
  padding    = "96",        -- marge autour du contenu

  -- ============ BRANDING ============
  -- Le logo s'affiche en bas-droite à 70% d'opacité, hauteur 56 px.
  -- Recommandé : PNG transparent ou avec son propre fond, 200-400 px de large,
  -- ~85 px de haut. Le chemin est relatif au dossier du template,
  -- ou absolu (`/Users/.../logo.png`).
  logo       = "logo.png",

  -- ============ ANIMATION ============
  -- Background animé :
  --   "static"    : fond plat (défaut)
  --   "mesh"      : blobs colorés dérivant (recommandé)
  --   "aurora"    : bandes ondulantes
  --   "grain"     : grain de film
  --   "particles" : petits points sparse
  motion     = "mesh",

  -- Stagger d'entrée des éléments :
  --   "stagger" (défaut) : chaque élément apparaît avec un léger délai
  --   "none"             : tout apparaît d'un coup
  -- animate = "stagger",

  -- Ken Burns sur images :
  --   true (défaut) : zoom lent + pan, donne de la vie aux photos
  --   false         : images statiques
  -- kenburns = true,

  -- ============ BARRE PRÉSENTATEUR ============
  -- Une barre 32 px en bas de l'écran affiche : timer écoulé,
  -- horloge HH:MM, slide N/total, le logo (ci-dessus) et un hint.
  -- Elle est toujours visible et fait office d'outil présentateur.

  -- ============ BARRE DU HAUT (optionnelle) ============
  -- Trois slots indépendants. La barre apparaît si AU MOINS un est rempli.
  -- Sinon, pas de barre du haut.
  -- topLeft   = "askem",
  -- topCenter = "Présentation déc 2025",
  -- topRight  = "v0.10",

  -- ============ AUTRES ============
  -- align       = "left",       -- "left", "center", "right"
  -- transition  = "fade",       -- "fade", "slide", "push", "none"
  -- showIndex   = "true",       -- "true" / "false"
  -- overflow    = "shrink",     -- "shrink" / "clip"
}
