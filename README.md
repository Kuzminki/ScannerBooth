# ScannerBooth

Application macOS SwiftUI pour parcourir la photothèque Photo Booth, redresser une photo de document, éclaircir le papier et enregistrer un PDF.

## Ouvrir et lancer

Ouvrez `ScannerBooth.xcodeproj` dans Xcode, choisissez la destination **My Mac**, puis lancez la cible `ScannerBooth`. L’application demande l’accès en lecture seule au paquet ou dossier `Photo Booth Library` et mémorise ce choix.

Dans l’écran de cadrage, faites glisser l’une des quatre poignées (zone de saisie agrandie) pour ajuster un coin. Le bouton **Actualiser l’aperçu** affiche le nouveau cadrage; si vous lancez l’export avant, le cadrage courant est recalculé automatiquement.

Sous l’aperçu, le sélecteur **Doc / Gray / N&B** choisit le rendu : couleur avec papier éclairci, niveaux de gris, ou noir et blanc à contraste élevé. Le changement de filtre actualise l’aperçu et s’applique au PDF exporté.

Cliquez sur **Enregistrer le PDF…** pour préparer le document puis choisir son emplacement dans la fenêtre d’enregistrement macOS. Une confirmation apparaît après l’enregistrement; fermer la fenêtre d’enregistrement annule l’opération.

La cible prend en charge macOS 14 et les versions ultérieures. Les images restent sur le Mac; l’app n’effectue pas d’OCR.

## Makefile

Le Makefile fournit des raccourcis pour Xcode :

- `make help` affiche les commandes disponibles.
- `make build` construit l’application dans `.build/DerivedData/`.
- `make run` construit puis lance l’application.
- `make open` ouvre le projet dans Xcode.
- `make install-app` copie l’application dans `~/Applications/` puis la lance.
- `make clean` supprime les produits de build dans `.build/`.

`make test` vérifie la compilation des sources XCTest, mais n’exécute pas les méthodes de test : le projet n’a pas encore de schéma Xcode partagé qui les inclut.

## Tests

La cible `ScannerBoothTests` contient des cas couvrant la conversion des coordonnées Vision, la validation du quadrilatère, le blanchiment du papier avec conservation de la couleur, les erreurs d’image et la création d’un PDF d’une page.
