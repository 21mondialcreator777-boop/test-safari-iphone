#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# safari-iphone.sh — ouvre une adresse dans le VRAI Safari d'un iPhone SIMULÉ (Xcode) et rapporte
# des captures d'écran et une vidéo du parcours.
#
# Écrit le 27/10/2026. Pourquoi : personne dans l'équipe n'a d'iPhone ni de Mac, et nos tests
# Playwright « WebKit » ne sont pas Safari. Le simulateur d'Apple, lui, embarque le Safari d'iOS.
#
# Ce que ça prouve : le RENDU tel que Safari iOS le dessine (verre flou, masques, polices, mise en
# page, lecture des vidéos), et le comportement au glissé de doigt simulé (idb).
# Ce que ça ne prouve PAS : la fluidité d'un vrai téléphone (GPU du Mac), ni la 4G.
#
# Usage : safari-iphone.sh <adresse> <modèle d'iPhone, ex. "iPhone 17"> <dossier de sortie>
# Codes : 0 = parcours fait · 2 = impossible de lancer l'iPhone simulé (rien n'est vérifiable)
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
ADRESSE="$1"; MODELE="$2"; SORTIE="$3"
mkdir -p "$SORTIE"
JOURNAL="$SORTIE/journal.txt"
dit() { echo "[$(date +%T)] $*" | tee -a "$JOURNAL"; }

# 1. Le runtime iOS le plus récent qui sait faire tourner ce modèle (avec l'Xcode choisi).
# IOS (variable, ex. « 18 ») impose la version : les runtimes sont PARTAGÉS entre les Xcode, donc
# choisir Xcode 16.4 ne suffit pas — le 27/10 l'« iPhone 16 iOS 18 » a tourné sous iOS 26.2.
CHOIX=$(python3 - "$MODELE" "${IOS:-}" <<'PY'
import json, subprocess, sys
modele, voulu = sys.argv[1], sys.argv[2]
runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"]))["runtimes"]
ios = [r for r in runtimes if r.get("platform") == "iOS" and r.get("isAvailable")
       and (not voulu or r["version"].split(".")[0] == voulu)]
ios.sort(key=lambda r: [int(x) for x in r["version"].split(".")], reverse=True)
for r in ios:
    for d in r.get("supportedDeviceTypes", []):
        if d["name"] == modele:
            print(r["identifier"], d["identifier"], r["version"], sep="|")
            sys.exit(0)
PY
)
if [ -z "$CHOIX" ]; then
  dit "NON VÉRIFIABLE : « $MODELE » n'existe dans aucun runtime iOS ${IOS:-} de cet Xcode. Runtimes et modèles :"
  xcrun simctl list runtimes | tee -a "$JOURNAL"
  xcrun simctl list devicetypes | grep -i iphone | tee -a "$JOURNAL"
  exit 2
fi
IFS='|' read -r RUNTIME TYPE VERSION <<< "$CHOIX"

# 2. On CRÉE notre propre iPhone (les identifiants préinstallés de l'image changent d'une version à l'autre).
UDID=$(xcrun simctl create "test-safari" "$TYPE" "$RUNTIME") || { dit "NON VÉRIFIABLE : création de l'iPhone refusée"; exit 2; }
dit "iPhone : $MODELE · iOS $VERSION · $UDID"
xcrun simctl boot "$UDID" || { dit "NON VÉRIFIABLE : l'iPhone ne démarre pas"; exit 2; }
borne 600 xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1; code=$?
[ "$code" = 0 ] || dit "démarrage : bootstatus rend le code $code (142 = délai de 600 s dépassé)"
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null || true
sleep 5

# borne <secondes> <commande…> : une commande bloquée ne fige plus tout le test (le 27/10, deux iPhone
# ont dépassé 30 min sans dire où). macOS n'a pas « timeout » : perl + alarm fait la même chose.
borne() { local s=$1; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }
DEBUT_PARCOURS=$(date +%s)
ecoule() { echo $(( $(date +%s) - DEBUT_PARCOURS )); }

# Le 27/10, 30 s ne suffisaient pas quand le simulateur charge une vidéo : 90 s, et un second essai.
capture() {
  borne 90 xcrun simctl io "$UDID" screenshot --type=png "$SORTIE/$1.png" > /dev/null 2>&1 && { dit "capture $1"; return; }
  sleep 5
  borne 90 xcrun simctl io "$UDID" screenshot --type=png "$SORTIE/$1.png" > /dev/null 2>&1 && dit "capture $1 (2e essai)" || dit "capture $1 RATÉE"
}

# 3. Préchauffage : le TOUT PREMIER lancement de Safari sur un iPhone neuf a pris 8 minutes
#    (mesuré le 27/10). On le fait AVANT de filmer, sinon la vidéo est 8 minutes d'attente (240 Mo).
debut=$(date +%s)
borne 600 xcrun simctl launch "$UDID" com.apple.mobilesafari > /dev/null 2>&1 || dit "préchauffage : Safari ne répond pas en 600 s"
sleep 10
dit "Safari préchauffé en $(( $(date +%s) - debut )) s"

# 4. Vidéo de tout le parcours (arrêtée proprement par SIGINT, sinon le fichier est illisible).
xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$SORTIE/parcours-brut.mp4" > /dev/null 2>&1 &
VIDEO=$!
sleep 3

# 5. Ouverture dans Safari, puis on laisse la page et sa vidéo d'accueil se charger.
debut=$(date +%s)
borne 300 xcrun simctl openurl "$UDID" "$ADRESSE" || dit "ouverture : pas de réponse en 300 s"
dit "ouverture de la page : $(( $(date +%s) - debut )) s"
sleep 20
capture "01-accueil"
# idb : le COMPAGNON doit être lancé à la main pour CET iPhone, puis le client lui parle sur
# localhost:10882 (doc fbidb). Le 27/10, `idb connect <udid>` seul échouait sans rien dire.
IDB_OK=0
if command -v idb > /dev/null 2>&1 && command -v idb_companion > /dev/null 2>&1; then
  idb_companion --udid "$UDID" > "$SORTIE/idb-compagnon.log" 2>&1 &
  for _ in $(seq 1 30); do nc -z localhost 10882 2> /dev/null && break; sleep 2; done
  export IDB_COMPANION=localhost:10882
  if borne 30 idb describe > "$SORTIE/idb-describe.txt" 2>&1; then
    IDB_OK=1; dit "idb : compagnon prêt sur localhost:10882"
  else
    dit "idb : le compagnon ne répond pas — $(tail -c 300 "$SORTIE/idb-describe.txt" | tr '
' ' ')"
    dit "idb : journal du compagnon — $(tail -c 300 "$SORTIE/idb-compagnon.log" | tr '
' ' ')"
  fi
else
  dit "idb : non installé (idb=$(command -v idb || echo absent), idb_companion=$(command -v idb_companion || echo absent))"
fi
# Au premier lancement, Safari 26 pose une bulle « View Bookmarks… » par-dessus la page : un toucher la ferme.
[ "$IDB_OK" = 1 ] && borne 15 idb ui tap 190 120 > /dev/null 2>&1 && sleep 2

# 6. Défilement au DOIGT simulé (idb envoie de vrais événements tactiles à iOS).
n=2
if [ "$IDB_OK" = 1 ]; then
  dit "défilement au doigt : idb prêt"
  for i in $(seq 1 40); do
    # Budget : on ne laisse pas le défilement manger le temps des sections.
    if [ "$(ecoule)" -gt 900 ]; then dit "défilement arrêté au glissé $i : budget de 15 min atteint"; break; fi
    t0=$(date +%s)
    if ! borne 20 idb ui swipe 190 520 190 170 --duration 0.5 > "$SORTIE/idb-glisse.txt" 2>&1; then
      dit "glissé $i refusé ou bloqué ($(( $(date +%s) - t0 )) s) : $(tail -c 200 "$SORTIE/idb-glisse.txt" | tr '
' ' ')"; break
    fi
    [ "$i" = 1 ] && dit "premier glissé : $(( $(date +%s) - t0 )) s"
    sleep 1.5
    if [ $((i % 4)) -eq 0 ]; then capture "$(printf '%02d' $n)-defilement-$i"; n=$((n + 1)); fi
  done
else
  dit "pas de défilement au doigt (idb indisponible, voir plus haut) : sections visitées par leurs ancres"
fi

# 7. Chaque section de la page, par son ancre (#id) : rendu de chaque chapitre, même sans idb.
ANCRES=$(curl -fsSL --max-time 30 "$ADRESSE" | grep -oE '<section[^>]* id="[^"]+"' | sed -E 's/.* id="([^"]+)".*/\1/' | head -15)
dit "sections : début à $(ecoule) s"
for ancre in $ANCRES; do
  borne 60 xcrun simctl openurl "$UDID" "${ADRESSE%/}/#$ancre"
  sleep 6
  capture "$(printf '%02d' $n)-section-$ancre"; n=$((n + 1))
done

# Retour en haut : l'accueil SANS la bulle de premier lancement.
borne 60 xcrun simctl openurl "$UDID" "${ADRESSE%/}/#"
sleep 8
capture "$(printf '%02d' $n)-accueil-final"

kill -INT "$VIDEO" 2> /dev/null; wait "$VIDEO" 2> /dev/null
# La vidéo brute fait ~20 Mo par minute : on la réduit avec l'outil intégré à macOS.
if [ -s "$SORTIE/parcours-brut.mp4" ] && borne 300 avconvert --source "$SORTIE/parcours-brut.mp4" --preset Preset960x540 \
     --output "$SORTIE/parcours.mp4" --replace > /dev/null 2>&1 && [ -s "$SORTIE/parcours.mp4" ]; then
  rm -f "$SORTIE/parcours-brut.mp4"
else
  mv -f "$SORTIE/parcours-brut.mp4" "$SORTIE/parcours.mp4" 2> /dev/null
fi
[ -s "$SORTIE/parcours.mp4" ] && dit "vidéo : $(du -h "$SORTIE/parcours.mp4" | cut -f1)" || dit "vidéo ABSENTE"

# 8. Planche contact : une page qui montre toutes les captures dans l'ordre.
{
  echo "<!doctype html><meta charset=utf-8><title>Safari $MODELE iOS $VERSION</title>"
  echo "<style>body{font:14px system-ui;background:#111;color:#eee;margin:16px}figure{display:inline-block;margin:8px;vertical-align:top}img{width:260px;border:1px solid #444}</style>"
  echo "<h1>$ADRESSE — $MODELE · iOS $VERSION</h1><p><a style=color:#9cf href=parcours.mp4>vidéo du parcours</a></p>"
  for f in "$SORTIE"/*.png; do b=$(basename "$f"); echo "<figure><img src=\"$b\"><figcaption>$b</figcaption></figure>"; done
} > "$SORTIE/index.html"
dit "fin : $(ls "$SORTIE"/*.png 2> /dev/null | wc -l) captures"
pkill -f "idb_companion --udid $UDID" 2> /dev/null || true
xcrun simctl shutdown "$UDID" > /dev/null 2>&1 || true
exit 0
