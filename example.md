---
theme: dark
accent: #ff7a59
titleSize: 84
fontSize: 36
padding: 90
align: left
transition: slide
transitionDuration: 0.35
---

# mSM

### .md Slide Machine

Un moteur de présentation minimal, écrit en Lua !

---

## Pourquoi ?

- Écrire des slides comme on écrit des notes
- Un seul fichier `.md`, versionnable
- Démarre en une seconde
- Pas de build, pas de CSS

---

## Format

En-tête YAML simple, puis du markdown.

Les slides sont séparées par une ligne `---`.

```
# Titre
## Sous-titre
- Puce
![alt](chemin/image.png)
```

---

## Images

![logo](assets/logo.png)

*(mettez une image dans `assets/` pour la voir ici)*

---

## Citations

> La simplicité est la sophistication suprême.

— attribué à Léonard de Vinci

---

## Inline markdown

Vous pouvez mettre du **gras**, de l'*italique*, du `code`, du ~~barré~~ et des [liens](https://love2d.org).

- Une puce avec **un mot fort**
- Une puce avec `une_fonction()` et *nuance*
- Combinaisons comme ***gras-italique*** sont gérées

> Citation avec **emphase** et `code` inline.

-> Paragraphe "note" préfixé par `->`, légèrement coloré.

-> Utile pour les réponses, *annotations* ou pensées secondaires.

  -> Indenter avec des espaces avant `->` pour un niveau secondaire.

    -> Deux niveaux d'indentation, etc.

---

## Transitions

Au choix dans l'en-tête :

- `fade`  — fondu enchaîné
- `slide` — glissement horizontal
- `push` — pousse + fondu
- `none` — coupe franche

---

## Tables

| Feature      | mSM   | Reveal.js | Marp    |
| ------------ | :---: | :-------: | :-----: |
| Format       |  md   |    md     |   md    |
| Runtime      |  Lua  |  JS/Web   |   CLI   |
| Dépendances  |   1   |    ++     |    +    |
| Transitions  |  oui  |   oui     | partiel |

*Note : les emojis (✅, ⚠️, …) sont silencieusement filtrés si la police ne les contient pas — pas de rectangles à l'écran.*

Alignement par colonne via `:---`, `:---:`, `---:` dans la ligne de séparation.

---

## Dépassement

Quand une slide est plus grande que la fenêtre, trois modes :

- `shrink` *(défaut)* : réduit l'échelle jusqu'à ce que tout rentre
- `clip`  : garde la taille, coupe ce qui dépasse
- `minScale: 0.45` : plancher d'échelle en mode shrink

Au-delà du plancher, mSM coupe automatiquement le bas.

Exemple : cette slide est volontairement longue pour tester.

- Point 1
- Point 2
- Point 3
- Point 4
- Point 5
- Point 6

---

## Raccourcis

- **→ / Espace / Clic gauche** : slide suivante
- **← / Clic droit** : slide précédente
- **Home / End** : première / dernière
- **F** : plein écran
- **R** : recharger le deck
- **Q / Échap** : quitter

---

# Merci.

### louis@askem.eu
