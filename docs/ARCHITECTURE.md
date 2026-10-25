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
| `lib/screens/admin/` | Administration : comptes, maintenance & mise à jour, code d'accès, journal |
| `lib/screens/common/system_screens.dart` | Écrans maintenance, mise à jour obligatoire, changement de mot de passe imposé |

Choix : `provider` suffit pour un état global limité à la session ; chaque écran charge ses données
avec un `FutureBuilder` et un rafraîchissement par glissement. Les listes d'appel et de cotisations accumulent les
modifications localement et les envoient en **un seul appel groupé** (utile avec une connexion mobile lente), avec
alerte si l'on quitte sans enregistrer.

## API (`backend/`)

| Fichier | Rôle |
|---|---|
| `src/server.js` | Migration puis écoute HTTP, arrêt propre (hébergement classique / Docker) |
| `api/index.js`, `vercel.json` | Point d'entrée Vercel : migrations au premier appel, région Francfort |
| `src/services/sms.js` | Envoi des codes SMS (Orange SMS API, Twilio) |
| `src/app.js` | Middlewares (helmet, CORS, limitation de débit), routes, gestion d'erreurs |
| `src/migrations/*.sql` | Schéma versionné (table `schema_migrations`) |
| `src/routes/` | `auth`, `children`, `events` (+ présences), `dues` (+ paiements), `posts`, `parent`, `payments`, `stats` |
| `src/services/importer.js` | Lecture Word/PDF/Excel/CSV et reconnaissance des colonnes |
| `src/services/wave.js` | Session Checkout, lien marchand, vérification de signature du webhook |
| `src/routes/admin.js` | Administration (rôle `admin` uniquement) |
| `src/services/settings.js` | Réglages en base : maintenance, version minimale, code d'accès responsable |
| `src/services/audit.js` | Journal des actions sensibles |
| `src/services/security.js` | Surveillance : événements suspects, détection d'injections, blocage d'IP, analyse des menaces |
| `src/services/dues.js` | Prix des cotisations par légion |
| `src/services/totp.js` | Codes d'application d'authentification (RFC 6238), chiffrement du secret, codes de secours |
| `src/create-admin.js` | `npm run create-admin` : crée/réinitialise un administrateur |
| `src/services/year.js` | Année pastorale (sept.→août), création des cotisations et activités par défaut |

### Modèle de données

```
users(id, role[admin|responsable|parent], full_name, phone UNIQUE, password_hash, legion, token_version, failed_logins, locked_until,
      disabled, must_change_password, last_login_at)
children(id, last_name, first_name, birth_date, age, legion, parent_name, parent_phone, address, link_code UNIQUE)
parent_children(parent_id → users, child_id → children)            -- lien établi par code enfant
events(id, kind[activite|reunion], name, event_date, year, position)
attendance(event_id → events, child_id → children, status[present|absent], marked_by → users)
dues(id, kind[paroissiale|diocesaine|activite], year, event_id → events, label, amount)   -- amount = prix commun
due_legion_amounts(due_id → dues, legion, amount)                   -- prix propre à une légion (prioritaire)
payments(due_id → dues, child_id → children, status[pending|paid], method[manuel|wave|wave_declare], amount, reference)
wave_sessions(id, due_id, child_id, parent_id, amount, status)
password_resets(id, user_id, code_hash, expires_at, attempts, used_at)
posts(id, title, body, pinned, created_by)
app_settings(key, value JSONB, updated_by, updated_at)            -- maintenance, app_update, signup_code
audit_log(id, actor_id, action, target, details JSONB, ip, created_at)
security_events(id, type, severity[info|warning|critical], ip, user_id, phone, path, details, created_at)  -- 90 jours
blocked_ips(ip, reason, blocked_by, expires_at)
login_challenges(id, user_id, code_hash, attempts, expires_at, used_at)  -- code SMS de connexion admin
```

Une cotisation non payée n'a pas de ligne dans `payments`. Montant dû par un enfant = prix de sa légion, sinon prix commun ;
le montant réellement payé est figé dans `payments.amount` (changer un prix ne modifie pas l'historique).

### Endpoints

Toutes les routes sont préfixées par `/api`. 🔒R = responsable (ou admin), 🔒P = parent, 🔒A = administrateur, 🔒 = connecté.

| Méthode | Route | Accès | Description |
|---|---|---|---|
| GET | `/health`, `/meta` | public | État, année en cours, légions, mode de paiement |
| POST | `/auth/register` | public | Création de compte (code d'accès requis pour un responsable) |
| POST | `/auth/login` | public | Connexion par téléphone + mot de passe (admin : renvoie `twoFactorRequired` + `challengeId`) |
| POST | `/auth/login/verify` | public | Administrateur : code (application, SMS ou code de secours) → session (12 h) |
| POST | `/auth/totp/setup`, `/auth/totp/enable` | 🔒A | Configurer l'application d'authentification (renvoie 8 codes de secours) |
| POST | `/auth/totp/disable`, `/auth/totp/recovery-codes` | 🔒A | Désactiver / nouveaux codes de secours (mot de passe exigé) |
| GET/PUT | `/auth/me` | 🔒 | Profil / modifier nom et téléphone (mot de passe actuel requis) |
| POST | `/auth/password`, `/auth/logout-all` | 🔒 | Changer le mot de passe / déconnecter tous les appareils |
| POST | `/auth/password/forgot` | public | Envoie un code SMS (réponse identique si le numéro est inconnu) |
| POST | `/auth/password/reset` | public | Code SMS + nouveau mot de passe → connecté |
| GET/POST | `/children` | 🔒R | Liste (filtres `legion`, `q`) / ajout |
| GET/PUT/DELETE | `/children/:id` | 🔒R | Détail / modification / suppression |
| POST | `/children/:id/regenerate-code` | 🔒R | Nouveau code enfant (retire l'accès des parents liés) |
| POST | `/children/import/preview` | 🔒R | Fichier (multipart `file`, 4 Mo max) → aperçu |
| POST | `/children/import/commit` | 🔒R | Enregistre les lignes validées |
| GET/POST | `/events` | 🔒R | Activités et réunions de l'année (`year`, `kind`) / création |
| PUT/DELETE | `/events/:id` | 🔒R | Intitulé, date, prix / suppression |
| GET/PUT | `/events/:id/attendance` | 🔒R | Feuille d'appel / enregistrement groupé |
| GET | `/dues` | 🔒R | Cotisations de l'année avec totaux |
| PUT | `/dues/:id` | 🔒R | Prix par légion `{amounts: {meneurs, aines, cadets, benjamins}}` (ancien format `{amount}` accepté) |
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

| GET | `/admin/overview` | 🔒A | Compteurs généraux |
| GET/POST | `/admin/users` | 🔒A | Liste (filtres `role`, `q`) / création avec mot de passe provisoire |
| PATCH/DELETE | `/admin/users/:id` | 🔒A | Rôle, légion, activer/désactiver / suppression |
| POST | `/admin/users/:id/reset-password`, `/admin/users/:id/logout` | 🔒A | Mot de passe provisoire / déconnexion forcée |
| GET | `/admin/settings` | 🔒A | Réglages |
| PUT | `/admin/settings/maintenance`, `/admin/settings/app-update` | 🔒A | Mode maintenance / version minimale et lien de mise à jour |
| POST | `/admin/settings/signup-code` | 🔒A | Nouveau code d'accès responsable |
| GET | `/admin/audit` | 🔒A | Journal |
| GET | `/admin/security` | 🔒A | Menaces détectées, remèdes, adresses actives, journal de sécurité |
| POST / DELETE | `/admin/security/block[/:ip]` | 🔒A | Bloquer (24 h, 7 j, définitif) / débloquer une adresse IP |

Garde-fous : impossible de se rétrograder ou se désactiver soi-même, ni de retirer le dernier administrateur.
En maintenance, seuls les administrateurs peuvent se connecter et utiliser l'API (503 pour les autres).
L'application interroge `/meta` au démarrage et au retour au premier plan : maintenance et mise à jour obligatoire
s'appliquent donc à **tous les téléphones déjà installés**, sans republier l'APK.

Erreurs : `{ "error": "message en français", "details": [{ "champ", "message" }] }`.
