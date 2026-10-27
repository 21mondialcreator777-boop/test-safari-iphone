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
CHOIX=$(python3 - "$MODELE" <<'PY'
import json, subprocess, sys
modele = sys.argv[1]
runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"]))["runtimes"]
ios = [r for r in runtimes if r.get("platform") == "iOS" and r.get("isAvailable")]
ios.sort(key=lambda r: [int(x) for x in r["version"].split(".")], reverse=True)
for r in ios:
    for d in r.get("supportedDeviceTypes", []):
        if d["name"] == modele:
            print(r["identifier"], d["identifier"], r["version"], sep="|")
            sys.exit(0)
PY
)
if [ -z "$CHOIX" ]; then
  dit "NON VÉRIFIABLE : « $MODELE » n'existe dans aucun runtime iOS de cet Xcode. Modèles disponibles :"
  xcrun simctl list devicetypes | grep -i iphone | tee -a "$JOURNAL"
  exit 2
fi
IFS='|' read -r RUNTIME TYPE VERSION <<< "$CHOIX"

# 2. On CRÉE notre propre iPhone (les identifiants préinstallés de l'image changent d'une version à l'autre).
UDID=$(xcrun simctl create "test-safari" "$TYPE" "$RUNTIME") || { dit "NON VÉRIFIABLE : création de l'iPhone refusée"; exit 2; }
dit "iPhone : $MODELE · iOS $VERSION · $UDID"
xcrun simctl boot "$UDID" || { dit "NON VÉRIFIABLE : l'iPhone ne démarre pas"; exit 2; }
xcrun simctl bootstatus "$UDID" -b > /dev/null
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null || true
sleep 5

capture() { xcrun simctl io "$UDID" screenshot --type=png "$SORTIE/$1.png" > /dev/null 2>&1 && dit "capture $1" || dit "capture $1 RATÉE"; }

# 3. Vidéo de tout le parcours (arrêtée proprement par SIGINT, sinon le fichier est illisible).
xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$SORTIE/parcours.mp4" > /dev/null 2>&1 &
VIDEO=$!
sleep 3

# 4. Ouverture dans Safari, puis on laisse la page et sa vidéo d'accueil se charger.
xcrun simctl openurl "$UDID" "$ADRESSE"
sleep 20
capture "01-accueil"

# 5. Défilement au DOIGT simulé (idb envoie de vrais événements tactiles à iOS).
n=2
if command -v idb > /dev/null 2>&1 && idb connect "$UDID" > /dev/null 2>&1; then
  dit "défilement au doigt : idb prêt"
  for i in $(seq 1 40); do
    if ! idb ui swipe 190 520 190 170 --duration 0.5 --udid "$UDID" > /dev/null 2>&1; then
      dit "glissé $i refusé par idb : arrêt du défilement"; break
    fi
    sleep 1.5
    if [ $((i % 4)) -eq 0 ]; then capture "$(printf '%02d' $n)-defilement-$i"; n=$((n + 1)); fi
  done
else
  dit "idb indisponible : pas de défilement au doigt (les sections sont quand même visitées par leurs ancres)"
fi

# 6. Chaque section de la page, par son ancre (#id) : rendu de chaque chapitre, même sans idb.
ANCRES=$(curl -fsSL --max-time 30 "$ADRESSE" | grep -oE '<section[^>]* id="[^"]+"' | sed -E 's/.* id="([^"]+)".*/\1/' | head -15)
for ancre in $ANCRES; do
  xcrun simctl openurl "$UDID" "${ADRESSE%/}/#$ancre"
  sleep 6
  capture "$(printf '%02d' $n)-section-$ancre"; n=$((n + 1))
done

kill -INT "$VIDEO" 2> /dev/null; wait "$VIDEO" 2> /dev/null
[ -s "$SORTIE/parcours.mp4" ] && dit "vidéo : $(du -h "$SORTIE/parcours.mp4" | cut -f1)" || dit "vidéo ABSENTE"

# 7. Planche contact : une page qui montre toutes les captures dans l'ordre.
{
  echo "<!doctype html><meta charset=utf-8><title>Safari $MODELE iOS $VERSION</title>"
  echo "<style>body{font:14px system-ui;background:#111;color:#eee;margin:16px}figure{display:inline-block;margin:8px;vertical-align:top}img{width:260px;border:1px solid #444}</style>"
  echo "<h1>$ADRESSE — $MODELE · iOS $VERSION</h1><p><a style=color:#9cf href=parcours.mp4>vidéo du parcours</a></p>"
  for f in "$SORTIE"/*.png; do b=$(basename "$f"); echo "<figure><img src=\"$b\"><figcaption>$b</figcaption></figure>"; done
} > "$SORTIE/index.html"
dit "fin : $(ls "$SORTIE"/*.png 2> /dev/null | wc -l) captures"
xcrun simctl shutdown "$UDID" > /dev/null 2>&1 || true
exit 0
