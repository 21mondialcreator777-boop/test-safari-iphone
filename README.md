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

## Video transparente : encoder et mesurer sa rotation

Le workflow `alpha-video.yml` convertit un média WebM public en ProRes4444, puis utilise
AVFoundation pour produire un HEVC avec alpha. `encoder-alpha.swift` décode toutes les images
exportées et vérifie les coins transparents, le contenu, les pixels partiellement transparents,
le nombre d'images et le budget de taille. Le MOV et son rapport sont des artefacts du run.

Le workflow `rotation-safari.yml` compare le JS publié et un candidat dans une copie locale de
la page complète, sur le Mac de test. Il ne déploie rien. Le candidat passe par l'entrée
`module_b64` et est masqué dans les journaux ; ne jamais y placer de secret ou de source de fabrication.
Le proxy charge les autres ressources depuis le domaine public. L'instrumentation positionne le
film au moment du formulaire et collecte temps média, images présentées, tours et pixels alpha.
Ces mesures ne sont pas un parcours au doigt ni une mesure de fluidité matérielle.

Attention à la bulle d'accueil Safari 26 : une seconde `simctl openurl` peut ne pas changer de
page. Exiger un journal émis depuis chaque origine ; un screenshot identique n'atteste pas une
nouvelle navigation. Le geste idb peut lui-même dépasser son délai, sans invalider les images
déjà réellement décodées. Lire les preuves avant de conclure à partir du statut du job.
