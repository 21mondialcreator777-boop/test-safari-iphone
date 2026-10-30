#!/bin/bash
set -euo pipefail
borne() { local s=$1; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }
CHOIX=$(python3 - <<'PY'
import json,os,subprocess
rs=json.loads(subprocess.check_output(['xcrun','simctl','list','runtimes','-j']))['runtimes']
for r in sorted(rs,key=lambda r:r['version'],reverse=True):
 if r.get('platform')=='iOS' and r.get('isAvailable') and r['version'].split('.')[0]==os.environ['IOS']:
  for d in r.get('supportedDeviceTypes',[]):
   if d['name']==os.environ['MODELE']:
    print(r['identifier']+'|'+d['identifier']); raise SystemExit
PY
)
IFS='|' read -r RUNTIME TYPE <<< "$CHOIX"
UDID=$(xcrun simctl create rotation-safari "$TYPE" "$RUNTIME")
echo "$MODELE $RUNTIME $UDID" | tee sortie/journal.txt
xcrun simctl boot "$UDID"
borne 600 xcrun simctl bootstatus "$UDID" -b > /dev/null
borne 600 xcrun simctl launch "$UDID" com.apple.mobilesafari > /dev/null
sleep 10
xcrun simctl status_bar "$UDID" override --time '9:41' --batteryState charged --batteryLevel 100 || true
IDB_OK=0
if command -v idb_companion > /dev/null && command -v idb > /dev/null; then
 idb_companion --udid "$UDID" > sortie/idb.log 2>&1 &
 export IDB_COMPANION=localhost:10882
 for _ in $(seq 1 30); do nc -z localhost 10882 2>/dev/null && break; sleep 2; done
 borne 30 idb describe > sortie/idb-description.txt 2>&1 && IDB_OK=1
fi
# Candidate first: Safari 26 can leave the initial tutorial bubble active and
# ignore the second external openurl. Each origin must actually send evidence.
for PORT in 8766 8765; do
  borne 180 xcrun simctl openurl "$UDID" "http://127.0.0.1:$PORT/prestations/index.html"
  sleep 20
  if [ "$IDB_OK" = 1 ]; then borne 30 idb ui tap 190 120 > /dev/null; fi
  for _ in $(seq 1 6); do
    [ -f "sortie/proof-$PORT.ndjson" ] && break
    borne 180 xcrun simctl openurl "$UDID" "http://127.0.0.1:$PORT/prestations/index.html"
    sleep 10
  done
  sleep 20
  for IMAGE in 1 2 3; do
    borne 90 xcrun simctl io "$UDID" screenshot --type=png "sortie/$PORT-$IMAGE.png"
    sleep 3
  done
done
python3 - <<'PY'
import json,pathlib
for port in [8765,8766]:
 p=pathlib.Path(f'sortie/proof-{port}.ndjson')
 rows=[json.loads(s) for s in p.read_text().splitlines()]
 ready=[r for r in rows if r.get('state')=='ready' and r.get('video') and not r['video']['paused']]
 times={round(r['video']['time'],2) for r in ready}
 print(port,'states',sorted({r.get('state','missing') for r in rows if r.get('state')}),'moving samples',len(times))
 if port==8766:
  assert len(times)>=5,'Candidate did not present moving transparent frames in Safari'
  assert any((r.get('inspection') or {}).get('turns',0)>=1 for r in ready),'No full rotation observed'
  assert all((r.get('inspection') or {}).get('alpha',{}).get('corners')==[0,0,0,0] for r in ready),'Lost alpha'
PY
