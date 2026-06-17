# mSM — personnaliser tes decks

Ce dossier `~/mSM/` est ton espace personnel pour configurer mSM : ton logo, tes couleurs, tes templates.

## Structure

```
~/mSM/
├── README.md              ← ce fichier
└── templates/
    └── askem/             ← template par défaut, créé au premier lancement
        ├── template.lua   ← palette, motion, logo, etc.
        └── logo.png       ← ton logo (remplaçable)
```

## Comment ça marche

À chaque ouverture d'un `.md`, mSM cherche `~/mSM/templates/askem/template.lua` et applique ses valeurs comme **défauts**. Toute clé écrite dans le frontmatter de ton deck **surcharge** la valeur du template.

Pas besoin d'écrire `template: askem` dans tes decks : c'est automatique.

## Personnaliser ton template askem

### Changer le logo

Remplace `~/mSM/templates/askem/logo.png` par le tien. Recommandations :

- PNG, fond transparent (ou ton fond préféré)
- Hauteur 80-120 px, largeur libre
- Affiché en bas-droite à 70% d'opacité, taillé à 56 px de haut

Si tu veux changer le placement, l'opacité ou la taille du logo, c'est dans le code de `main.lua` (cherche `draw logo`).

### Changer les couleurs

Édite `~/mSM/templates/askem/template.lua`. Toutes les clés sont commentées dans le fichier, voici les principales :

```lua
return {
  background = "#0f1620",   -- fond
  color      = "#e8eef7",   -- texte
  accent     = "#4ec9ff",   -- titres niveau 1
  h2         = "#ffd166",   -- titres niveau 2
  h3         = "#a5d8a7",   -- titres niveau 3
  muted      = "#7a8a9f",   -- secondaire (quotes, index)
  note       = "#b8c8de",   -- paragraphes "-> note"
}
```

### Changer le fond animé

Cinq options pour `motion` :

| Valeur | Effet |
|---|---|
| `static` | Fond plat, sans animation |
| `mesh` | Blobs colorés qui dérivent (recommandé) |
| `aurora` | Bandes ondulantes |
| `grain` | Grain de film léger |
| `particles` | Petits points sparse qui dérivent |

### Désactiver les animations

```lua
return {
  -- ...
  motion   = "static",
  animate  = "none",
  kenburns = false,
}
```

## Créer d'autres templates

Pour avoir un "minimal" en plus de "askem" :

```bash
mkdir -p ~/mSM/templates/minimal
```

Crée `~/mSM/templates/minimal/template.lua` avec tes valeurs. Puis dans le `.md` du deck qui doit utiliser ce template :

```yaml
---
template: minimal
---
```

## Surcharger par deck

Toute valeur peut être surchargée à la pièce dans un `.md` :

```yaml
---
accent: "#ff7a59"      # override la couleur accent du template
motion: aurora         # override le fond animé
logo: /tmp/promo.png   # override le logo (chemin absolu)
template: none         # désactive complètement le template
---
```

## Toutes les clés disponibles

Voir le `template.lua` fourni dans `~/mSM/templates/askem/` : chaque clé y est documentée.

## Plus d'info

Le README principal de mSM est dans le repo : <https://gitlab.com/xpoxpo/msm>
