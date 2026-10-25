# ScannerBooth

Application macOS SwiftUI pour parcourir la photothèque Photo Booth, redresser une photo de document, éclaircir le papier et enregistrer un PDF.

## Ouvrir et lancer

Ouvrez `ScannerBooth.xcodeproj` dans Xcode, choisissez la destination **My Mac**, puis lancez la cible `ScannerBooth`. L’application mémorise l’accès au paquet ou dossier `Photo Booth Library` choisi et lit les photos qu’il contient. Elle conserve les originaux et écrit les PDF dans le dossier sélectionné pour l’export.

Dans l’écran de cadrage, faites glisser l’une des quatre poignées (zone de saisie agrandie) pour ajuster un coin. Le bouton **Actualiser l’aperçu** affiche le nouveau cadrage; si vous lancez l’export avant, le cadrage courant est recalculé automatiquement.

Sous l’aperçu, le sélecteur **Doc / Gray / N&B** choisit le rendu : couleur avec papier éclairci, niveaux de gris, ou noir et blanc à contraste élevé. Le changement de filtre actualise l’aperçu et s’applique au PDF exporté.

Cliquez sur **Enregistrer le PDF…** puis choisissez un dossier de destination. L’app utilise le sélecteur modal `NSOpenPanel`, puis enregistre le PDF sous le nom `<nom-de-la-photo>_scan.pdf`. Si ce nom existe déjà, elle ajoute un numéro pour ne pas écraser le fichier existant. Le cadrage et le filtre courants sont traités après le choix du dossier; une confirmation apparaît après l’écriture.

### Diagnostic de l’export PDF

L’app journalise l’état du bouton Exporter, l’action du clic, l’état des fenêtres avant la présentation, la réponse de `NSOpenPanel`, l’accès au dossier et les erreurs d’écriture dans le journal unifié macOS. Pour suivre ces événements, lancez cette commande dans Terminal avant de cliquer sur **Enregistrer le PDF…**, puis copiez les lignes affichées :

```sh
log stream --style compact --level info --predicate 'subsystem == "com.guilhem.ScannerBooth" AND category == "PDFExport"'
```

Pour consulter les événements déjà enregistrés des cinq dernières minutes :

```sh
log show --last 5m --style compact --predicate 'subsystem == "com.guilhem.ScannerBooth" AND category == "PDFExport"'
```

La cible prend en charge macOS 14 et les versions ultérieures. Les images restent sur le Mac; l’app n’effectue pas d’OCR.

## Makefile

Le Makefile fournit des raccourcis pour Xcode :

- `make help` affiche les commandes disponibles.
- `make build` construit l’application dans `.build/DerivedData/`.
- `make run` arrête l’ancienne instance, construit l’application, met à jour `~/Applications/ScannerBooth.app`, compare les exécutables et affiche leurs empreintes SHA-256, puis enregistre et lance cette copie. La cible confirme que le processus actif utilise bien l’exécutable dans `~/Applications/` et échoue si ce contrôle ne passe pas.
- `make open` ouvre le projet dans Xcode.
- `make install-app` copie l’application dans `~/Applications/` puis lance cette copie.
- `make clean` supprime les produits de build dans `.build/`.

`make run` lance le bundle copié depuis le dernier `xcodebuild` réussi de cette même commande. La comparaison des empreintes vérifie la copie, puis le contrôle de processus vérifie le chemin effectivement ouvert par macOS.

`make test` vérifie la compilation des sources XCTest, mais n’exécute pas les méthodes de test : le projet n’a pas encore de schéma Xcode partagé qui les inclut.

## Tests

La cible `ScannerBoothTests` contient des cas couvrant la conversion des coordonnées Vision, la validation du quadrilatère, le blanchiment du papier avec conservation de la couleur, les erreurs d’image et la création d’un PDF d’une page.
