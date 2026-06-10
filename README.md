# mSM — .md Slide Machine

Un moteur de slides en Lua / [LÖVE2D](https://love2d.org) qui lit un simple fichier `.md` : en-tête de style minimal, contenu markdown, images, transitions.

---

## Deux runtimes

- **Desktop** (Lua / LÖVE2D) — fenêtre native, rapide, offline complet.
- **Web** (`msm.html`) — navigateur, zéro install, partageable par URL.

Les deux parsent exactement la même syntaxe et supportent les mêmes options de frontmatter.

## 1. Version desktop (LÖVE)

Installer LÖVE 11+ (`brew install --cask love` sur macOS), puis :

```bash
love . chemin/vers/deck.md
```

Sans argument, mSM affiche un écran d'accueil — glisser-déposer un `.md` sur la fenêtre le charge.

### 1bis. App macOS pour le Dock (`mSM.app`)

Packagez une vraie application macOS qui accepte les `.md` en drop sur son icône du Dock :

```bash
./package-mac.sh
mv mSM.app /Applications/
open /Applications/mSM.app      # premier lancement : macOS enregistre l'app
```

Puis glissez `mSM.app` sur le Dock pour l'épingler. Drag d'un `.md` sur l'icône → ouverture dans mSM.

**Dans l'app** :

- Toutes les touches habituelles (flèches, F plein écran, Q quitter).
- **`E`** : exporte le deck courant en HTML autonome — dialogue de sauvegarde macOS natif, images base64-inlinées, un seul `.html` partageable.

Le script fait : zip des sources Lua + `msm.html` → fusion avec le binaire `love` → patch `Info.plist` (exécutable, bundle id, `CFBundleDocumentTypes` pour `md`/`markdown`) → signature ad-hoc → nettoyage quarantine.

## 2. Version web (`msm.html`)

Un unique fichier HTML, pas de dépendances, pas de build. Trois façons de l'utiliser, du plus simple au plus autonome :

### a. Glisser-déposer (pas de serveur)

Ouvrir `msm.html` directement (double-clic → `file://...`). Glisser un `.md` sur la page : le deck se charge.

- Les images fonctionnent si elles sont **co-localisées avec `msm.html`** (mêmes chemins relatifs).
- Recommandé pour une démo rapide sur son propre poste.

### b. Serveur local (toutes les features, répertoires arbitraires)

```bash
cd mdslidemachine
python3 -m http.server 8000
# puis ouvrir http://localhost:8000/msm.html?deck=example.md
```

Les chemins d'images relatifs sont résolus par rapport à l'URL du deck. `fetch()` ne marche pas en `file://` — d'où le serveur.

### c. Build → HTML autonome (partage, offline total)

```bash
lua build.lua example.md                     # → example.html
lua build.lua example.md mon-deck.html       # nom de sortie explicite
```

Le script :

- Lit `msm.html` comme template.
- Inline le markdown dans un `<script type="text/plain">`.
- Base64-encode **toutes les images locales** référencées dans le deck et les convertit en `data:` URLs.

Résultat : **un seul fichier `.html`, double-cliquable, hors-ligne, partageable par mail ou Drive**. Fonctionne sans serveur, sans install, sur n'importe quel navigateur récent.

Nécessite simplement `lua` (≥ 5.1) dans le PATH, et `base64` (pré-installé sur macOS/Linux).

### Avantages du runtime web

- Emojis rendus nativement (Apple Color Emoji sur macOS, etc.)
- Aucun problème de glyphe manquant
- Plein écran via `F`, partageable par URL
- Performance fluide sur tout laptop récent

---

## Format d'un deck

Un deck est un fichier markdown composé de :

1. **Un en-tête optionnel** (frontmatter YAML) entre deux lignes `---`.
2. **Des slides** séparées par une ligne `---`.

Exemple minimal :

```markdown
---
theme: dark
transition: fade
---

# Première slide

Du texte.

---

# Deuxième slide

- une puce
- une autre
```

---

## En-tête : options de style

Toutes les clés sont optionnelles. Les couleurs sont en hexadécimal (`#rrggbb`).

| Clé                   | Défaut    | Rôle                                                |
| --------------------- | --------- | --------------------------------------------------- |
| `theme`               | `dark`    | Preset : `dark`, `light`, `cream`, `slate`, `solar` |
| `background`          | (thème)   | Couleur de fond                                     |
| `color`               | (thème)   | Couleur du texte                                    |
| `accent`              | (thème)   | Couleur des titres `#` et des accents              |
| `h2`                  | (thème)   | Couleur des titres `##`                             |
| `h3`                  | (thème)   | Couleur des titres `###`                            |
| `note`                | (thème)   | Couleur des paragraphes `-> …`                      |
| `muted`               | (thème)   | Couleur secondaire (citations, puces creuses)       |
| `font`                | système   | Chemin vers un `.ttf` ou `.otf`                     |
| `fontSize`            | `34`      | Taille du corps de texte                            |
| `titleSize`           | `72`      | Taille des titres `#`                               |
| `codeSize`            | `24`      | Taille des blocs de code                            |
| `padding`             | `80`      | Marge intérieure en pixels                          |
| `lineSpace`           | `8`       | Espace vertical entre éléments                      |
| `align`               | `left`    | `left`, `center`, `right`                           |
| `transition`          | `fade`    | `fade`, `slide`, `push`, `none`                     |
| `transitionDuration`  | `0.35`    | Durée de la transition en secondes                  |
| `showIndex`           | `true`    | Affiche `n / total` en bas à droite                 |
| `overflow`            | `shrink`  | Gestion du dépassement : `shrink` ou `clip`         |
| `minScale`            | `0.45`    | Échelle minimum en mode `shrink` avant clipping     |

Un preset définit six couleurs (`background`, `color`, `accent`, `h2`, `h3`, `muted`) ; toute couleur explicite dans le frontmatter a la priorité.

#### Palette par preset

| preset  | `#` (accent) | `##` (h2)  | `###` (h3) | muted     |
| ------- | ------------ | ---------- | ---------- | --------- |
| `dark`  | orange       | sky blue   | violet     | slate     |
| `light` | blue         | teal       | purple     | gray      |
| `cream` | terracotta   | olive      | brown      | khaki     |
| `slate` | sky blue     | violet     | pink       | slate     |
| `solar` | yellow       | blue       | magenta    | gray      |

---

## Syntaxe d'une slide

| Markdown          | Résultat                                               |
| ----------------- | ------------------------------------------------------ |
| `# Titre`         | Gros titre en couleur d'accent                         |
| `## Sous-titre`   | Titre de niveau 2                                      |
| `### Petit`       | Titre de niveau 3 en couleur secondaire                |
| `- item` / `* item` | Puce                                                 |
| `> citation`      | Citation avec barre latérale                           |
| `-> note`         | Paragraphe "note/réponse" en couleur distincte (indentation = 2 espaces par niveau avant `->`) |
| `` ```…``` ``     | Bloc de code monospace                                 |
| `![alt](path)`    | Image centrée, adaptée à la taille de la slide         |
| `\| a \| b \|`    | Table (header, séparateur, lignes)                     |
| `**gras**`        | Gras                                                   |
| `*italique*`      | Italique                                               |
| `` `code` ``      | Code inline (fond teinté)                              |
| `~~barré~~`       | Texte barré                                            |
| `[texte](url)`    | Lien (accent + souligné)                               |
| *(ligne vide)*    | Espace vertical                                        |
| *(tout le reste)* | Paragraphe de texte                                    |

### Tables

```markdown
| Colonne A | Colonne B | Colonne C |
| --------- | :-------: | --------: |
| gauche    | centré    | à droite  |
| a         | b         | c         |
```

La ligne de séparation pilote l'alignement par colonne :

- `:---` ou `---`  → gauche (défaut)
- `:---:`          → centré
- `---:`           → droite

La largeur des colonnes s'ajuste au contenu ; si le total dépasse la largeur disponible, mSM met à l'échelle proportionnellement.

### Dépassement vertical

Quand une slide est plus haute que l'espace disponible, `overflow` choisit la stratégie :

- **`shrink`** *(défaut)* : réduit l'échelle du contenu pour qu'il rentre.
- **`clip`** : garde la taille, coupe ce qui dépasse au bas du cadre.

`minScale` (défaut `0.45`) est le plancher en mode `shrink`. Si le contenu est tellement grand qu'il faudrait descendre en dessous, mSM s'arrête à `minScale` et clippe le reste — pour éviter le texte illisible.

### Glyphes manquants

mSM supprime silencieusement tout caractère absent de la police courante (par défaut : Bitstream Vera Sans, fournie par LÖVE). Pas de petits rectangles "tofu" à l'écran.

Si tu as besoin d'une couverture Unicode plus large (langues non latines, symboles typographiques avancés), pointe une police plus complète dans le frontmatter :

```
font: /System/Library/Fonts/Supplemental/Arial Unicode.ttf
```

Les emojis couleur d'Apple ne sont pas rendus — FreeType ne les supporte pas. Ils sont simplement retirés.

### Rendu du markdown inline (desktop)

mSM utilise la famille Arial (Regular + Bold + Italic + Bold Italic) comme police par défaut sur macOS (chemins `/System/Library/Fonts/Supplemental/`). C'est un vrai bold / italic — distinct du regular.

Si tu pointes `font:` vers un chemin de fichier, mSM cherche aussi ses variantes à côté (conventions `-Bold`, `-Italic`, `-BoldItalic`, avec espace ou sans).

Styles inline pris en charge :

- **gras** : vraie police Bold si disponible, sinon triple-impression décalée (pseudo-bold).
- *italique* : vraie police Italic si disponible, sinon `love.graphics.shear` (slant).
- `code` : fond teinté accent + police monospace.
- ~~barré~~ : ligne horizontale traversante.
- [lien](…) : couleur accent + soulignement (cliquable en web uniquement).

Sur le runtime web, ce sont les vraies balises HTML (`<strong>`, `<em>`, `<code>`, `<s>`, `<a>`).

> **Limites connues** : puces imbriquées, titres avec `#` multiples sur la même ligne, markdown dans les cellules de table (les marqueurs sont retirés, le style n'est pas appliqué côté desktop).

### Séparateurs de slides

- `---` (la convention)
- `===` aussi accepté, utile si tu veux garder `---` pour autre chose dans le corps.

### Chemins d'images

Les chemins relatifs sont résolus à partir du dossier du `.md`. Les chemins absolus fonctionnent aussi.

---

## Transitions

- **fade** : fondu enchaîné entre les deux slides.
- **slide** : l'ancienne sort, la nouvelle entre par l'autre côté.
- **push** : l'ancienne se fane en sortant, la nouvelle arrive.
- **none** : coupe franche.

Pour un deck avec zéro animation : `transition: none` + `transitionDuration: 0`.

---

## Raccourcis clavier

| Touche                                     | Action               |
| ------------------------------------------ | -------------------- |
| `→` / `Espace` / `Entrée` / `↓` / `PgDn`   | Slide suivante       |
| `←` / `↑` / `Retour arrière` / `PgUp`      | Slide précédente     |
| `Home` / `End`                             | Première / dernière  |
| `F`                                        | Bascule plein écran  |
| `R`                                        | Recharge le deck     |
| `E`                                        | Exporter en HTML autonome (dialogue de sauvegarde) |
| `Tab`                                      | Ouvrir le `.md` dans l'éditeur par défaut (MarkEdit, …) |
| `⌘E`                                       | Éditer la slide courante dans l'app (source markdown brute) |
| `⌘S` (en édition)                          | Enregistrer + sortir du mode édition |
| `Esc` (en édition)                         | Annuler les modifications |
| Clic en édition                            | Place le curseur                     |
| Drag souris en édition                     | Sélectionne                          |
| Double-clic en édition                     | Sélectionne le mot                   |
| Triple-clic en édition                     | Sélectionne la ligne                 |
| `⌥`+flèches en édition                     | (non géré, voir Limites)             |
| `⇧`+flèches/home/end en édition            | Étend la sélection                   |
| `⌥`+←/→ en édition                          | Saut de mot                          |
| `⌘A` / `⌘C` / `⌘X` / `⌘V` en édition       | Tout sélectionner / copier / couper / coller |
| `⌘Z` / `⌘⇧Z` (ou `⌘Y`) en édition           | Undo / Redo                          |
| `Q` / `Échap`                              | Quitter              |

L'app surveille aussi le `.md` sur disque : si tu l'édites dans une autre app (MarkEdit via `Tab` par exemple) et que tu sauvegardes, mSM recharge automatiquement le deck en conservant la slide courante.
| Clic gauche / molette bas                  | Suivante             |
| Clic droit / molette haut                  | Précédente           |

Glisser-déposer un `.md` sur la fenêtre charge ce deck.

---

## Structure du projet

```
mdslidemachine/
├── main.lua          # runtime desktop : boucle LÖVE, rendu, transitions, input
├── parser.lua        # parser markdown (frontmatter + slides + éléments)
├── inline.lua        # parser + layout + rendu du markdown inline (gras, italique, ...)
├── exporter.lua      # génère le HTML autonome (partagé CLI + app)
├── conf.lua          # fenêtre, identité LÖVE
├── msm.html          # runtime web : parser + rendu + input, single-file
├── build.lua         # CLI : deck.md (+ images) → deck.html autonome
├── package-mac.sh    # construit mSM.app (bundle macOS drag-drop)
├── icon-gen/         # générateur d'icône (LÖVE → PNG)
├── icon.png          # icône générée (1024×1024, régénérable)
├── example.md        # deck de démonstration
└── README.md         # ce fichier
```

## Étendre

- **Ajouter un thème** : complète la table `THEMES` dans `main.lua`.
- **Ajouter un élément markdown** : ajoute une branche dans `parse_slide` (parser.lua), puis un rendu dans `draw_slide` (main.lua).
- **Ajouter une transition** : ajoute une branche dans `love.draw` sous `trans_t < 1`.

## Licence

MIT.
