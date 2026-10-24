# Sécurité

L'application manipule des **données de mineurs** (noms, âges, adresses, contacts des parents). Les choix ci-dessous
visent à limiter qui peut voir quoi.

## Contrôle d'accès
- **Inscription responsable fermée par défaut** : sans `RESPONSABLE_SIGNUP_CODE` côté serveur, personne ne peut créer
  de compte responsable. Le code est comparé en temps constant. Changez-le si un ancien responsable le connaît encore.
- **Parents cloisonnés** : un parent ne voit que les enfants rattachés à son compte par le **code enfant**
  (8 caractères aléatoires, alphabet sans caractères ambigus, ~10¹² combinaisons, 20 essais par heure et par compte).
  Le code n'est jamais renvoyé aux parents. « Générer un nouveau code » retire l'accès de tous les parents liés.
- Le rattachement par simple numéro de téléphone a été écarté : n'importe qui pourrait créer un compte avec le numéro
  d'un autre parent et voir ses enfants.
- Toutes les routes responsables sont protégées par rôle côté serveur (pas seulement masquées dans l'app).

## Authentification
- Mots de passe hachés avec **bcrypt** (8 caractères minimum).
- **JWT HS256** (7 jours) avec `token_version` : changer de mot de passe ou « déconnecter tous les appareils » invalide
  immédiatement les anciens jetons. `JWT_SECRET` obligatoire (≥ 32 caractères) en production.
- **Blocage 15 min après 5 échecs** de connexion, limitation de débit sur l'authentification, réponse en temps
  constant que le numéro existe ou non.
- Jeton stocké dans le **Keystore Android** (`flutter_secure_storage`), sauvegarde Android désactivée (`allowBackup=false`).

## Transport et API
- HTTP en clair interdit dans l'APK (`usesCleartextTraffic=false`) : l'API doit être servie en HTTPS.
- `helmet`, CORS fermé par défaut (l'app mobile n'en a pas besoin), limitation globale (300 req/min/IP).
- Validation stricte de toutes les entrées (`zod`), requêtes SQL paramétrées uniquement.
- Import : 5 Mo maximum, formats limités, traitement en mémoire, rien n'est enregistré avant validation.

## Paiements
- L'app ne marque **jamais** seule une cotisation comme payée.
- Mode Checkout : seul le **webhook signé** par Wave (HMAC-SHA256, horodatage ±5 min) confirme le paiement, après
  vérification du montant et de la session. Un paiement confirmé par Wave ne peut pas être décoché par erreur.
- Mode lien marchand : le parent ne peut que **déclarer** (« à confirmer ») ; un responsable valide.

## Points à traiter avant la mise en production
- **Réinitialisation de mot de passe** : non automatisée (pas d'envoi de SMS). Aujourd'hui un administrateur doit le
  faire en base ; un envoi d'OTP par SMS (Orange/MTN, Twilio…) est l'évolution logique.
- **Gestion des responsables** : tous les responsables ont les mêmes droits ; il n'y a pas d'écran pour révoquer un
  compte (à faire en base : `DELETE FROM users WHERE ...`).
- **Sauvegardes** de la base à planifier chez l'hébergeur.
- **Consentement** : informer les parents de la collecte de ces données (loi ivoirienne n° 2013-450 sur les données
  personnelles, ARTCI).
