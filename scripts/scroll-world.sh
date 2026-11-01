#!/bin/bash
set -euo pipefail
borne(){ local seconds=$1;shift;perl -e 'alarm shift;exec @ARGV' "$seconds" "$@"; }
CHOIX=$(python3 - <<'PY'
import json,os,subprocess
rs=json.loads(subprocess.check_output(['xcrun','simctl','list','runtimes','-j']))['runtimes']
for r in sorted(rs,key=lambda r:r['version'],reverse=True):
 if r.get('platform')=='iOS' and r.get('isAvailable') and r['version'].split('.')[0]==os.environ['IOS']:
  for d in r.get('supportedDeviceTypes',[]):
   if d['name']==os.environ['MODELE']:
    print(r['identifier']+'|'+d['identifier']);raise SystemExit
PY
)
IFS='|' read -r RUNTIME TYPE <<< "$CHOIX"
UDID=$(xcrun simctl create scroll-world "$TYPE" "$RUNTIME")
echo "$MODELE $RUNTIME $UDID" | tee sortie-scroll/journal.txt
xcrun simctl boot "$UDID"
borne 600 xcrun simctl bootstatus "$UDID" -b >/dev/null
borne 600 xcrun simctl launch "$UDID" com.apple.mobilesafari >/dev/null
idb_companion --udid "$UDID" >sortie-scroll/idb.log 2>&1 &
export IDB_COMPANION=localhost:10882
for _ in $(seq 1 30);do nc -z localhost 10882 2>/dev/null && break;sleep 2;done
borne 30 idb describe >sortie-scroll/idb-description.txt
for PORT in 8766 8765;do
 xcrun simctl terminate "$UDID" com.apple.mobilesafari || true
 if ! borne 180 xcrun simctl openurl "$UDID" "http://127.0.0.1:$PORT/";then
  sleep 3
  borne 180 xcrun simctl openurl "$UDID" "http://127.0.0.1:$PORT/" || true
 fi
 for _ in $(seq 1 12);do [ -f "sortie-scroll/proof-$PORT.ndjson" ] && break;sleep 5;done
 sleep 5
 borne 90 xcrun simctl io "$UDID" screenshot --type=png "sortie-scroll/$PORT-before.png"
 for GESTURE in $(seq 1 8);do
  if ! borne 30 idb ui swipe 190 520 190 170 --delta 50 --duration 0.5 >>sortie-scroll/gestures.log 2>&1;then
   echo "NON VERIFIABLE: gesture $GESTURE timed out" | tee -a sortie-scroll/journal.txt;break
  fi
  sleep 1
 done
 sleep 5
 borne 90 xcrun simctl io "$UDID" screenshot --type=png "sortie-scroll/$PORT-after.png"
done
python3 - <<'PY'
import json,pathlib
result={}
for port in [8765,8766]:
 file=pathlib.Path(f'sortie-scroll/proof-{port}.ndjson')
 if not file.exists():result[str(port)]={'verdict':'NON VERIFIABLE: no page evidence'};continue
 rows=[json.loads(s) for s in file.read_text().splitlines()]
 live=[r for r in rows if not r['hidden']]
 result[str(port)]={'touchmove':max(r['counts']['touchmove'] for r in live),'pointermove':max(r['counts']['pointermove'] for r in live),'scroll':max(r['scrollY'] for r in live),'hashes':len({r['hash'] for r in live}),'images':len({r['diagnostic']['image'] for r in live}),'totalVh':live[-1]['diagnostic']['total'],'lastFilmTime':live[-1]['diagnostic']['t']}
 print(port,result[str(port)])
pathlib.Path('sortie-scroll/result.json').write_text(json.dumps(result,indent=2))
for port in [8766,8765]:
 candidate=result[str(port)]
 assert candidate.get('touchmove',0)>=3,f'NON VERIFIABLE: no actual touch pan on {port}'
 assert candidate['hashes']>=3 and candidate['images']>=3,f'ROUGE: film remained visually frozen on {port}'
 if port==8766:assert 2000<=candidate['totalVh']<=3600,'ROUGE: wrong candidate cadence'
PY
