/**
 * Haku Pi — généré le 27/08/2026
 * settings.js Node-RED pour le voilier Haku (Amel 50) — Raspberry Pi 4, Bookworm.
 *
 * Ce fichier est copié par install.sh vers ~/.node-red/settings.js.
 * Tous les secrets viennent de /etc/haku/haku.env, injecté par systemd
 * (drop-in systemd/nodered-override.conf → EnvironmentFile).
 *
 * Points clés :
 *  - adminAuth ACTIVÉ : l'éditeur (http://haku:1880/) exige NR_ADMIN_USER +
 *    mot de passe dont le hash bcrypt est NR_ADMIN_HASH (scripts/gen-adminauth.sh).
 *    Tant que le hash n'est pas généré, le placeholder ci-dessous ne correspond
 *    à AUCUN mot de passe : l'éditeur est verrouillé (comportement voulu).
 *  - Le dashboard (http://haku:1880/dashboard) reste accessible sans
 *    authentification : il est réservé au LAN du bord + Tailscale par le
 *    pare-feu nftables (rien n'est exposé côté WAN, Starlink est en CGNAT).
 *  - contextStorage « file » : persiste le mode MOUILLAGE/MARINA, l'état des
 *    alertes et les stats du jour sur la carte SD (flush toutes les 30 s,
 *    volume d'écriture négligeable).
 */

module.exports = {
    /* ------------------------------------------------------------------ */
    /* Fichier de flux et écoute réseau                                    */
    /* ------------------------------------------------------------------ */
    flowFile: 'flows.json',
    flowFilePretty: true,

    uiPort: process.env.PORT || 1880,
    // Bind sur toutes les interfaces : le filtrage se fait par nftables
    // (LAN du bord + interface tailscale0 uniquement).
    uiHost: '0.0.0.0',

    // v1.1 — Fichiers statiques servis par Node-RED (même port 1880, donc
    // couverts par le pare-feu) :
    //  - /static/  : Leaflet vendu en LOCAL dans le dépôt (aucun CDN à bord)
    //  - /tracks/  : index.geojson + fichiers GPX pour la carte Navigations
    httpStatic: [
        { path: process.env.HAKU_STATIC || '/opt/haku/static/', root: '/static/' },
        { path: (process.env.TRACKS_DIR || '/var/lib/haku/tracks') + '/', root: '/tracks/' }
    ],

    /* ------------------------------------------------------------------ */
    /* Sécurité                                                            */
    /* ------------------------------------------------------------------ */
    adminAuth: {
        type: 'credentials',
        users: [
            {
                username: process.env.NR_ADMIN_USER || 'admiral',
                // Placeholder invalide par construction : générer le vrai hash
                // avec sudo /opt/haku/scripts/gen-adminauth.sh
                password: process.env.NR_ADMIN_HASH ||
                    'HASH-NON-GENERE-lancer-gen-adminauth.sh',
                permissions: '*'
            }
        ]
    },

    // Les flux Haku ne stockent AUCUN credential (MQTT Cerbo sans auth sur le
    // LAN, SMTP géré hors Node-RED par scripts/send-alert.sh). La valeur fixe
    // évite la régénération d'une clé aléatoire à chaque déploiement.
    credentialSecret: process.env.NR_CRED_SECRET || 'haku-sans-credentials',

    /* ------------------------------------------------------------------ */
    /* Persistance de contexte (mode MARINA/MOUILLAGE, alertes, stats)     */
    /* ------------------------------------------------------------------ */
    contextStorage: {
        default: { module: 'memory' },
        file: {
            module: 'localfilesystem',
            config: {
                // Écrit au plus toutes les 30 s et seulement si modifié :
                // usure SD négligeable.
                flushInterval: 30
            }
        }
    },

    /* ------------------------------------------------------------------ */
    /* Runtime                                                             */
    /* ------------------------------------------------------------------ */
    functionGlobalContext: {},
    functionExternalModules: false,
    externalModules: {
        autoInstall: false
    },

    // Reconnexion MQTT/websocket : le Pi retente indéfiniment (bateau inoccupé).
    mqttReconnectTime: 15000,
    socketReconnectTime: 10000,

    // v1.1.1 — taille maximale des corps de requêtes HTTP (POST /journal…) :
    // large marge au-dessus d'une ligne de journal, mais borne les abus.
    apiMaxLength: '256kb',

    debugMaxLength: 1000,

    /* ------------------------------------------------------------------ */
    /* Journalisation : vers la console → journald (volatile, en RAM)      */
    /* ------------------------------------------------------------------ */
    logging: {
        console: {
            level: 'info',
            metrics: false,
            audit: false
        }
    },

    /* ------------------------------------------------------------------ */
    /* Éditeur                                                             */
    /* ------------------------------------------------------------------ */
    editorTheme: {
        header: {
            title: 'Haku — Node-RED'
        },
        tours: false,
        projects: {
            enabled: false
        }
    }
};
