# Test Safari iPhone (gratuit)

Ouvre un site dans le **vrai Safari d'iPhones simulés** par Apple (Xcode), sur les Mac que GitHub prête
gratuitement aux dépôts publics, et rapporte des **captures d'écran** et une **vidéo** du parcours.

Appareils testés à chaque lancement :

| iPhone | iOS | Pourquoi |
|---|---|---|
| iPhone 17 | 26 | le Safari des iPhone récents |
| iPhone SE (3rd generation) | 26 | petit écran |
| iPhone 16 | 18 | les clientes qui n'ont pas mis à jour |

## Lancer un test

Onglet **Actions** › **Safari iPhone** › **Run workflow** › (adresse à tester) › **Run workflow**.
Environ 10 minutes. Les résultats sont en bas de la page du lancement, rubrique **Artifacts** :
un dossier par iPhone, avec `index.html` (planche de toutes les captures), `parcours.mp4` et `journal.txt`.

## Ce que ça prouve, et ce que ça ne prouve pas

- ✅ Le **rendu** tel que Safari iOS le dessine : verre flou, masques, polices, mise en page, vidéos qui se lancent ou non.
- ✅ Le **défilement au doigt simulé** (outil idb), qui envoie de vrais événements tactiles à iOS.
- ❌ La **fluidité** d'un vrai téléphone : le simulateur utilise la carte graphique du Mac.
- ❌ La 4G et la mémoire d'un vrai iPhone. Pour ça : un vrai iPhone.

Aucun secret dans ce dépôt : le test charge seulement l'adresse publique du site.
