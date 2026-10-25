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
- **Blocage 15 min après 5 échecs** de connexion, réponse en temps constant que le numéro existe ou non.
- Limitation de débit : 100 requêtes d'authentification / 15 min par adresse IP (beaucoup de parents partagent la
  même IP derrière l'opérateur mobile) **et** 10 / 15 min par numéro de téléphone visé.
- Comptes désactivés ou supprimés : jetons refusés immédiatement (vérification en base à chaque requête).
- Jeton stocké dans le **Keystore Android** (`flutter_secure_storage`), sauvegarde Android désactivée (`allowBackup=false`).

## Mot de passe oublié
- Code à 6 chiffres aléatoire, stocké uniquement sous forme d'empreinte HMAC, valable 10 minutes, usage unique.
- 5 essais maximum par code, 3 demandes par heure et par compte, réponse identique que le numéro existe ou non.
- Le changement de mot de passe déconnecte tous les appareils et lève un éventuel blocage de connexion.

## Transport et API
- HTTP en clair interdit dans l'APK (`usesCleartextTraffic=false`) : l'API doit être servie en HTTPS.
- `helmet`, CORS fermé par défaut (l'app mobile n'en a pas besoin), limitation globale (300 req/min/IP).
  Sur Vercel, ces compteurs sont propres à chaque instance de fonction : ils freinent sans garantir une limite stricte.
  Les protections critiques (blocage de connexion, essais de code SMS, demandes de code) sont, elles, stockées en base.
- Validation stricte de toutes les entrées (`zod`), requêtes SQL paramétrées uniquement.
- Import : 4 Mo maximum, formats limités, traitement en mémoire, rien n'est enregistré avant validation.

## Paiements
- L'app ne marque **jamais** seule une cotisation comme payée.
- Mode Checkout : seul le **webhook signé** par Wave (HMAC-SHA256, horodatage ±5 min) confirme le paiement, après
  vérification du montant et de la session. Un paiement confirmé par Wave ne peut pas être décoché par erreur.
- Mode lien marchand : le parent ne peut que **déclarer** (« à confirmer ») ; un responsable valide.

## Administration et maintenance
- **Double vérification** : après le mot de passe, un code à 6 chiffres est exigé. De préférence lu dans une
  **application d'authentification** (Google / Microsoft Authenticator, norme TOTP : sans réseau ni SMS, secret
  chiffré en base AES-256-GCM, code non réutilisable) avec **8 codes de secours** à usage unique en cas de perte du
  téléphone (Profil › Application d'authentification). À défaut, le code est envoyé par SMS au numéro de l'administrateur
  (5 min, usage unique, 5 essais par code, 10 demandes / 15 min). Sans le téléphone, pas d'accès, même avec le mot de passe.
- Session administrateur limitée à **12 h** ; mot de passe administrateur : **12 caractères** minimum, lettres et chiffres.
- « Mot de passe oublié » d'un administrateur : ne connecte pas directement, il faut ensuite mot de passe + code SMS.
- Nommer un nouvel administrateur exige de confirmer avec son propre mot de passe.
- **Alerte SMS** à l'administrateur en cas d'échecs sur son compte (au plus une par heure).
- Secours (SMS en panne et application non configurée) : variable `ADMIN_2FA=off` dans Vercel puis redéploiement ;
  remettre `on` ensuite. Attention : changer `JWT_SECRET` rend illisibles les secrets d'application (à reconfigurer).
- Rôle `admin` distinct, impossible à obtenir par l'inscription (champ `role` ignoré, testé).
- Comptes créés par l'admin : mot de passe provisoire aléatoire, **changement obligatoire** à la première connexion
  (toutes les autres routes répondent 403 tant qu'il n'est pas changé).
- Le dernier administrateur ne peut être ni supprimé, ni désactivé, ni rétrogradé. Changer un rôle ou désactiver un
  compte déconnecte tous ses appareils.
- Les actions sensibles (comptes, réglages, suppression d'enfant, nouveau code enfant) sont inscrites au journal.
- Lien de mise à jour : `https://` uniquement.

## Surveillance des attaques (Administration › Sécurité)
Sont enregistrés (90 jours, jamais de mot de passe, numéros masqués) : échecs de connexion, comptes bloqués, échecs
et connexions administrateur, codes SMS erronés, jetons falsifiés, accès à des fonctions interdites, comptes désactivés,
tentatives d'injection (SQL, script, traversée de répertoires, clés `$`/`__proto__`), faux avis de paiement Wave,
limitations de débit, codes enfant erronés.

L'écran analyse les dernières 24 h et affiche les **menaces** (force brute depuis une adresse, compte ciblé depuis
plusieurs adresses, injections, faux paiements, jetons falsifiés) avec **la marche à suivre** et un bouton d'action :
bloquer l'adresse IP (24 h, 7 jours ou définitif) ou ouvrir le compte visé. Chaque événement du journal a son conseil.
Impossible de bloquer sa propre adresse. Les écritures du journal sont plafonnées (120 / min / instance) pour qu'un
attaquant ne puisse pas remplir la base.

## Tests d'intrusion (`backend/test/security.test.js` et `legion-security.test.js`, 34 scénarios, OWASP API Top 10)
| Catégorie | Attaques testées | Résultat |
|---|---|---|
| Injection SQL | `' OR 1=1--`, `UNION SELECT`, `; DROP TABLE`, dans recherche, identifiants, légion, année, connexion, code enfant ; injection de second ordre | Bloquées (requêtes paramétrées, validation) |
| Injection NoSQL / pollution de prototype | `{"$ne":null}`, `__proto__`, `constructor.prototype` | Rejetées (400) |
| XSS stockée | `<script>`, `<img onerror>` dans noms et informations | Stockées comme texte, servies en JSON `nosniff` |
| JWT | `alg: none`, signature forgée, HS512, jeton expiré, `sub` invalide | Refusés (401) |
| Accès aux données d'autrui (BOLA/IDOR) | Parent lisant un enfant non rattaché, parent sur routes responsable | Refusés (403/404) |
| Élévation de privilèges | `role: admin` à l'inscription, responsable sur `/admin`, assignation de masse | Refusées |
| Force brute | Mots de passe, codes SMS, codes enfant, en-tête `X-Forwarded-For` falsifié | Limités (429 / blocage) |
| Déni de service | JSON géant, fichier > 4 Mo, **bombe ZIP** (docx/xlsx), ReDoS | Refusés (413 / 400) |
| Paiement | Webhook Wave non signé, rejeu, double paiement, montant modifié | Refusés |
| Fuites | Empreintes de mots de passe, code enfant côté parent, traces d'erreurs, énumération des numéros | Aucune fuite |

### Failles trouvées et corrigées pendant l'audit
1. **Plantage serveur (500)** si le téléphone envoyé n'était pas une chaîne (`{"toString":1}`) → contrôle de type.
2. **Limitation trop large et contournable** : une seule limite par IP bloquait tous les parents d'un même opérateur
   et ne protégeait pas un compte visé depuis plusieurs IP → limite par IP + par numéro.
3. **`X-Forwarded-For` falsifiable** : l'adresse IP n'était pas fiable derrière un proxy → `trust proxy` réglé sur
   l'hébergeur uniquement (Vercel).
4. **Bombe ZIP** : un `.docx` de 4 Mo pouvait se décompresser en plusieurs Go → contrôle de la taille décompressée
   (40 Mo) et du nombre de fichiers avant lecture.
5. **Recherche** : `%` et `_` interprétés comme jokers (contournement de filtre, requêtes lentes) → échappés.
6. **Clé des codes SMS** identique au secret des jetons → clé dérivée (HKDF).
7. **Comptes responsables impossibles à révoquer** → désactivation / suppression depuis l'administration.
8. **Signature de l'APK** : clé de test publique → clé définitive chiffrée dans le dépôt (secret GitHub).
9. Dépendances : versions figées, `npm audit` = 0 vulnérabilité.

## Points à traiter avant la mise en production
- **Fournisseur SMS** à configurer (Orange SMS API ou Twilio) pour activer « Mot de passe oublié ».
- Sur Vercel, les compteurs de débit sont propres à chaque instance : le blocage de compte (en base) reste la
  protection principale. Contrepartie connue : un attaquant peut bloquer un compte 15 min en se trompant 5 fois.
- **Sauvegardes** de la base à planifier chez l'hébergeur.
- **Consentement** : informer les parents de la collecte de ces données (loi ivoirienne n° 2013-450 sur les données
  personnelles, ARTCI).
