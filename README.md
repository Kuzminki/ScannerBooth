# ScannerBooth

Application macOS SwiftUI pour parcourir la photothèque Photo Booth, redresser une photo de document, éclaircir le papier et enregistrer un PDF.

## Ouvrir et lancer

Ouvrez `ScannerBooth.xcodeproj` dans Xcode, choisissez la destination **My Mac**, puis lancez la cible `ScannerBooth`. L’application mémorise l’accès au paquet ou dossier `Photo Booth Library` choisi et lit les photos qu’il contient. Elle conserve les originaux et écrit les PDF dans le dossier sélectionné pour l’export.

Dans l’écran de cadrage, la détection privilégie les quadrilatères qui couvrent une part importante de la photo afin d’éviter les cadres internes du formulaire. Si aucun contour de page assez grand n’est trouvé, ajustez manuellement les quatre poignées (zone de saisie agrandie). Le bouton **Actualiser l’aperçu** affiche le nouveau cadrage; si vous lancez l’export avant, le cadrage courant est recalculé automatiquement.

Sous l’aperçu, le sélecteur **Doc / Gray / N&B** choisit le rendu : couleur avec papier éclairci, niveaux de gris, ou noir et blanc à contraste élevé. Le changement de filtre actualise l’aperçu et s’applique au PDF exporté.

Les curseurs **Netteté** et **Blancheur du papier** règlent l’accentuation des détails et l’éclaircissement non linéaire des tons clairs. Le réglage de blancheur préserve davantage le texte et les détails sombres. Les deux curseurs sont mémorisés entre les utilisations de l’application et leurs valeurs s’appliquent à l’aperçu et au PDF.

Cliquez sur **Enregistrer le PDF…** pour ouvrir le dialogue d’enregistrement macOS. Le nom proposé est `<nom-de-la-photo>_scan.pdf`, et le champ reste modifiable. Choisissez aussi le dossier de destination; le cadrage et le filtre courants sont traités ensuite. Une confirmation apparaît après l’écriture.

### Diagnostic de l’export PDF

L’app journalise l’état du bouton Exporter, l’action du clic, l’état des fenêtres avant la présentation, la visibilité et la réponse de `NSSavePanel`, l’accès au dossier et les erreurs d’écriture dans le journal unifié macOS. Pour suivre ces événements, lancez cette commande dans Terminal avant de cliquer sur **Enregistrer le PDF…**, puis copiez les lignes affichées :

```sh
log stream --style compact --level info --predicate 'subsystem == "com.guilhem.ScannerBooth" AND category == "PDFExport"'
```

Pour consulter les événements déjà enregistrés des cinq dernières minutes :

```sh
log show --last 5m --style compact --predicate 'subsystem == "com.guilhem.ScannerBooth" AND category == "PDFExport"'
```

La détection écrit aussi le nombre de rectangles Vision retenus et la taille/confiance du cadrage choisi :

```sh
log stream --style compact --level info --predicate 'subsystem == "com.guilhem.ScannerBooth" AND category == "DocumentDetection"'
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
