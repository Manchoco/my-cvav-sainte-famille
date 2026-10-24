# Architecture

```
┌──────────────────────────┐   HTTPS / JSON + JWT   ┌──────────────────────────┐      ┌──────────────┐
│ App Flutter (APK)        │ ─────────────────────▶ │ API Express (Node 22)    │ ───▶ │ PostgreSQL   │
│ provider · http          │                        │ zod · helmet · rate-limit│      └──────────────┘
│ flutter_secure_storage   │ ◀── ouverture Wave ──┐ │ multer + mammoth/pdf/xlsx│
└──────────────────────────┘                      │ └────────────▲─────────────┘
                                                  │              │ webhook signé (HMAC)
                                           ┌──────┴──────────────┴─┐
                                           │ Wave (app + Checkout) │
                                           └───────────────────────┘
```

## Application mobile (`app/`)

| Dossier | Rôle |
|---|---|
| `lib/main.dart` | Démarrage, localisation française, aiguillage selon la session (accueil / responsable / parent) |
| `lib/config.dart` | URL de l'API (`--dart-define=API_URL`, modifiable dans l'app) |
| `lib/api/api_client.dart` | Client HTTP : jeton Bearer, délais, messages d'erreur en français, déconnexion sur 401 |
| `lib/api/repository.dart` | Appels typés vers chaque endpoint |
| `lib/models.dart` | Modèles (Child, EventItem, Due, ParentDue…), légions et formats (F CFA, dates) |
| `lib/state/session.dart` | Session (`ChangeNotifier`), jeton dans le Keystore Android |
| `lib/theme.dart` | Charte graphique tirée des logos (bleu CVAV `#1A9AD6`, marine `#0B3A57`, or `#F2B544`) |
| `lib/widgets/common.dart` | Composants partagés : états vide/erreur/chargement, badges de légion, en-tête |
| `lib/screens/common/` | Accueil, connexion/inscription, informations, profil |
| `lib/screens/responsable/` | Tableau de bord, enfants (+ import), présences, cotisations |
| `lib/screens/parent/` | Accueil parent, présences, informations & paiement Wave |

Choix : `provider` suffit pour un état global limité à la session ; chaque écran charge ses données
avec un `FutureBuilder` et un rafraîchissement par glissement. Les listes d'appel et de cotisations accumulent les
modifications localement et les envoient en **un seul appel groupé** (utile avec une connexion mobile lente), avec
alerte si l'on quitte sans enregistrer.

## API (`backend/`)

| Fichier | Rôle |
|---|---|
| `src/server.js` | Migration puis écoute HTTP, arrêt propre |
| `src/app.js` | Middlewares (helmet, CORS, limitation de débit), routes, gestion d'erreurs |
| `src/migrations/*.sql` | Schéma versionné (table `schema_migrations`) |
| `src/routes/` | `auth`, `children`, `events` (+ présences), `dues` (+ paiements), `posts`, `parent`, `payments`, `stats` |
| `src/services/importer.js` | Lecture Word/PDF/Excel/CSV et reconnaissance des colonnes |
| `src/services/wave.js` | Session Checkout, lien marchand, vérification de signature du webhook |
| `src/services/year.js` | Année pastorale (sept.→août), création des cotisations et activités par défaut |

### Modèle de données

```
users(id, role[responsable|parent], full_name, phone UNIQUE, password_hash, legion, token_version, failed_logins, locked_until)
children(id, last_name, first_name, birth_date, age, legion, parent_name, parent_phone, address, link_code UNIQUE)
parent_children(parent_id → users, child_id → children)            -- lien établi par code enfant
events(id, kind[activite|reunion], name, event_date, year, position)
attendance(event_id → events, child_id → children, status[present|absent], marked_by → users)
dues(id, kind[paroissiale|diocesaine|activite], year, event_id → events, label, amount)
payments(due_id → dues, child_id → children, status[pending|paid], method[manuel|wave|wave_declare], amount, reference)
wave_sessions(id, due_id, child_id, parent_id, amount, status)
posts(id, title, body, pinned, created_by)
```

Une cotisation non payée n'a pas de ligne dans `payments`. Le prix d'une activité est porté par sa ligne `dues`.

### Endpoints

Toutes les routes sont préfixées par `/api`. 🔒R = responsable, 🔒P = parent, 🔒 = connecté.

| Méthode | Route | Accès | Description |
|---|---|---|---|
| GET | `/health`, `/meta` | public | État, année en cours, légions, mode de paiement |
| POST | `/auth/register` | public | Création de compte (code d'accès requis pour un responsable) |
| POST | `/auth/login` | public | Connexion par téléphone + mot de passe |
| GET | `/auth/me` | 🔒 | Profil |
| POST | `/auth/password`, `/auth/logout-all` | 🔒 | Changer le mot de passe / déconnecter tous les appareils |
| GET/POST | `/children` | 🔒R | Liste (filtres `legion`, `q`) / ajout |
| GET/PUT/DELETE | `/children/:id` | 🔒R | Détail / modification / suppression |
| POST | `/children/:id/regenerate-code` | 🔒R | Nouveau code enfant (retire l'accès des parents liés) |
| POST | `/children/import/preview` | 🔒R | Fichier (multipart `file`, 5 Mo max) → aperçu |
| POST | `/children/import/commit` | 🔒R | Enregistre les lignes validées |
| GET/POST | `/events` | 🔒R | Activités et réunions de l'année (`year`, `kind`) / création |
| PUT/DELETE | `/events/:id` | 🔒R | Intitulé, date, prix / suppression |
| GET/PUT | `/events/:id/attendance` | 🔒R | Feuille d'appel / enregistrement groupé |
| GET | `/dues` | 🔒R | Cotisations de l'année avec totaux |
| PUT | `/dues/:id` | 🔒R | Montant |
| GET/PUT | `/dues/:id/payments` | 🔒R | Enfants payé / non payé / à confirmer ; cochage groupé |
| GET | `/stats` | 🔒R | Tableau de bord |
| GET | `/posts` | 🔒 | Informations |
| POST/PUT/DELETE | `/posts[/:id]` | 🔒R | Gestion des informations |
| POST | `/parent/link` | 🔒P | Rattacher un enfant avec son code |
| DELETE | `/parent/children/:id` | 🔒P | Retirer un enfant |
| GET | `/parent/children`, `/parent/attendance`, `/parent/dues` | 🔒P | Données des seuls enfants rattachés |
| POST | `/payments/wave/checkout` | 🔒P | URL Wave (session Checkout ou lien marchand) |
| POST | `/payments/declare` | 🔒P | Déclarer un paiement (mode lien marchand) |
| POST | `/payments/wave/webhook` | signature Wave | Confirmation automatique |
| GET | `/payments/wave/retour` | public | Page de retour après paiement |

Erreurs : `{ "error": "message en français", "details": [{ "champ", "message" }] }`.
