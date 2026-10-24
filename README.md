# My CVAV Sainte Famille

Application Android (APK) des **Cœurs Vaillants – Âmes Vaillantes** de l'Externat Sainte Famille (Cocody Riviera II) :
liste des enfants par légion, appel aux activités et réunions, cotisations, informations, et paiement par **Wave**.

| Accueil | Espace responsable | Espace parent |
|---|---|---|
| ![Accueil](docs/captures/01-accueil.png) | ![Responsable](docs/captures/02-responsable-accueil.png) | ![Parent](docs/captures/04-parent.png) |

```
cvav/
├── app/        Application Flutter (Android ; version web possible)
├── backend/    API REST Node.js + PostgreSQL
├── docs/       Architecture, API, sécurité, parcours et captures
├── render.yaml Déploiement de l'API en un clic sur Render
└── .github/workflows/build-apk.yml  Tests + compilation automatique de l'APK
```

## Fonctionnalités

**Responsable** (inscription protégée par un code d'accès)
- **Enfants** : nom, prénoms, âge ou date de naissance, contact et nom des parents, lieu d'habitation, répartis en
  **Meneurs, Aînés, Cadets, Benjamins**. Recherche, fiche détaillée, appel ou WhatsApp au parent.
- **Import de liste** depuis **Word (.docx), PDF, Excel (.xlsx) ou CSV**. L'application reconnaît les colonnes usuelles
  (« Nom », « Prénoms », « Âge », « Date de naissance », « Contact des parents », « Lieu d'habitation », « Légion ») et les
  titres de section (« Légion des Cadets »…). Un **aperçu modifiable** est affiché avant l'enregistrement, les doublons sont signalés.
- **Présences** : les 7 activités de l'année sont créées automatiquement (Rentrée pastorale, Accueil des nouveaux,
  Camp de jumelage, Happy New Year, Ressourcement spirituel, Cérémonie d'ascension personnelle, Mini camp biblique +
  Journée sportive) ; on ajoute les réunions. Appel par légion, boutons P / A, « restants présents », nom du responsable qui a pointé.
- **Cotisations** : paroissiale (1 500 F par défaut), diocésaine (montant à fixer), activités (prix fixé par activité).
  Liste des enfants par légion, on coche ceux qui ont payé. Les paiements Wave déclarés par les parents sont mis en évidence pour confirmation.
- **Informations** : publication, épinglage, modification et suppression d'annonces lues par les parents.

**Parent**
- Rattache ses enfants avec le **code enfant** (8 caractères) donné par le responsable.
- **Présences et absences** de ses enfants, par ordre alphabétique, avec taux d'assiduité.
- **Informations** : annonces et **cotisations à payer** (montant, type, activité), bouton **PAYER LA COTISATION**
  qui ouvre **Wave** avec le montant.

## Démarrage rapide (développement)

Prérequis : Node.js 20+, PostgreSQL 14+, Flutter 3.47+.

```bash
# API
cd backend
cp .env.example .env          # renseigner DATABASE_URL, JWT_SECRET, RESPONSABLE_SIGNUP_CODE
npm install
npm run seed                  # données de démo (facultatif)
npm run dev                   # http://localhost:3000/api/health
npm test                      # 20 tests d'intégration (base cvav_test)

# Application
cd ../app
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:3000   # émulateur Android
```

Comptes de démo créés par `npm run seed` : responsable `0700000001`, parent `0700000002`, mot de passe `cvav2026`.

## Obtenir l'APK

### Option 1 : GitHub Actions (recommandée, aucun outil à installer)
1. Créez un dépôt GitHub et poussez ce dossier.
2. Dans *Settings → Secrets and variables → Actions → Variables*, ajoutez `API_URL` = l'adresse de votre API déployée.
3. Onglet *Actions → Tests et APK → Run workflow*. À la fin, téléchargez l'artefact **my-cvav-sainte-famille-apk**.
4. Pour une version à distribuer, créez une clé de signature (une seule fois, à conserver précieusement) :
   ```bash
   keytool -genkey -v -keystore cvav.jks -keyalg RSA -keysize 2048 -validity 10000 -alias cvav
   base64 -w0 cvav.jks   # contenu du secret ANDROID_KEYSTORE_BASE64
   ```
   puis ajoutez les secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
   Un tag `v1.0.0` publie l'APK dans *Releases*.

### Option 2 : sur votre ordinateur (Android Studio installé)
```bash
cd app
flutter build apk --release --dart-define=API_URL=https://votre-api.exemple.com
# -> app/build/app/outputs/flutter-apk/app-release.apk
```

L'adresse de l'API peut aussi être changée dans l'application : **appui long sur le logo CVAV** de l'écran d'accueil.

## Déployer l'API

- **Render** : *New → Blueprint* avec ce dépôt (fichier `render.yaml`), puis renseigner `RESPONSABLE_SIGNUP_CODE`,
  `PUBLIC_BASE_URL` (ex. `https://my-cvav-api.onrender.com`) et la configuration Wave.
  ⚠️ Sur l'offre gratuite, le service s'endort après 15 min d'inactivité (premier chargement ≈ 50 s) et la base
  PostgreSQL gratuite de Render expire au bout de 30 jours : pour garder les données, utilisez une base gratuite
  durable (Neon, Supabase) via `DATABASE_URL` + `DATABASE_SSL=true`, ou une offre payante.
- **Docker** : `docker build -t my-cvav-api backend && docker run -p 3000:3000 --env-file backend/.env my-cvav-api`.

Les migrations SQL sont appliquées automatiquement au démarrage.

## Paiement Wave

Deux modes, choisis par les variables d'environnement de l'API :

| Mode | Configuration | Fonctionnement |
|---|---|---|
| **Wave Business (Checkout API)** — recommandé | `WAVE_API_KEY`, `WAVE_WEBHOOK_SECRET`, `PUBLIC_BASE_URL` ; webhook Wave → `https://VOTRE-API/api/payments/wave/webhook` | L'API crée une session de paiement au bon montant, Wave s'ouvre, et le **webhook signé** marque automatiquement la cotisation comme payée. |
| **Lien marchand** | `WAVE_MERCHANT_LINK` (ex. `https://pay.wave.com/m/M_ci_XXXX/c/ci/`) | Wave s'ouvre avec le montant. Au retour, le parent déclare son paiement (n° de transaction facultatif) ; un responsable le confirme en cochant l'enfant. |

Sans aucune des deux, le bouton affiche « paiement Wave non configuré ». Le format exact du lien marchand et
l'activation de l'API Checkout sont à vérifier auprès de Wave Business pour votre compte.

## Documentation

- [Architecture, modèle de données et API](docs/ARCHITECTURE.md)
- [Sécurité](docs/SECURITE.md)
- [Parcours utilisateurs et écrans](docs/PARCOURS.md)
