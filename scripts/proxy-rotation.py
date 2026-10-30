"""Local test copy of the public page. No deployed site is changed.
8765 = published JS, 8766 = candidate JS. All other bytes come from the same site.
"""
import base64, hashlib, http.server, json, os, pathlib, re, threading, urllib.request
from urllib.parse import urlsplit

patch = base64.b64decode(os.environ['MODULE_B64'])
print('candidate SHA256', hashlib.sha256(patch).hexdigest(), flush=True)
cache = pathlib.Path('cache'); cache.mkdir(exist_ok=True)
proof = pathlib.Path('sortie'); proof.mkdir(exist_ok=True)
audit_js = b'''
import {inspectKeycap} from '/prestations/js/keycap-estimation.js';
let ticks=0;
const seek=setInterval(()=>{
 if(window.PIFILM){window.PIFILM.allerAuTemps(58,'auto');clearInterval(seek);}
},250);
setInterval(()=>{
 const button=document.querySelector('.cue[data-cue=agent] .lead-submit--keycap');
 const v=button?.querySelector('video');
 const item={tick:++ticks,at:Date.now(),state:button?.dataset.keycapState,mode:button?.dataset.keycapMode,
  inspection:button?inspectKeycap(button):null,video:v?{time:v.currentTime,paused:v.paused,ready:v.readyState,src:v.currentSrc,error:v.error?.code}:null,
  rect:button?{x:button.getBoundingClientRect().x,y:button.getBoundingClientRect().y,width:button.getBoundingClientRect().width,height:button.getBoundingClientRect().height}:null,
  viewport:[innerWidth,innerHeight],hidden:document.hidden};
 fetch('/__proof',{method:'POST',body:JSON.stringify(item)}).catch(()=>{});
},1000);
'''

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass
    def do_POST(self):
        if self.path != '/__proof': self.send_error(405); return
        item=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))))
        with open(proof / f'proof-{self.server.server_port}.ndjson','a') as out:
            out.write(json.dumps(item)+'\n')
        self.send_response(204); self.end_headers()
    def do_GET(self):
        path=urlsplit(self.path).path
        fixed=self.server.server_port==8766
        if path=='/__audit.js': data=audit_js; mime='text/javascript'
        elif path.endswith('/keycap-estimation.js') and fixed: data=patch; mime='text/javascript'
        elif path.endswith('/touche-estimation-360-safari.mov'):
            data=pathlib.Path('media/touche-estimation-360-safari.mov').read_bytes(); mime='video/quicktime'
        else:
            digest=hashlib.sha256(path.encode()).hexdigest()
            file=cache/digest; meta=cache/(digest+'.mime')
            if not file.exists():
                try:
                    with urllib.request.urlopen('https://parisimmo.re'+path,timeout=60) as remote:
                        body=remote.read(); content=remote.headers.get('Content-Type','application/octet-stream')
                    file.write_bytes(body); meta.write_text(content)
                except Exception as err:
                    print(path,str(err),flush=True); self.send_error(502); return
            data=file.read_bytes(); mime=meta.read_text()
            if 'text/html' in mime:
                data=data.replace(b'</body>',b'<script type="module" src="/__audit.js"></script></body>')
            # Give the decoder a composited frame during the alpha probe; opacity:0
            # can suppress video presentation callbacks. Only in candidate copy.
            if fixed and path.endswith('.css'):
                data+=b'\n.lead-submit--keycap[data-keycap-state="probing"] .lead-keycap-film{opacity:.001}\n'
        total=len(data); start=0; end=total-1
        range_header=self.headers.get('Range')
        if range_header:
            found=re.fullmatch(r'bytes=(\d+)-(\d*)',range_header)
            if found:
                start=int(found[1]); end=min(int(found[2]),end) if found[2] else end
                if start>end: self.send_error(416); return
                self.send_response(206); self.send_header('Content-Range',f'bytes {start}-{end}/{total}')
            else: self.send_error(416); return
        else: self.send_response(200)
        self.send_header('Content-Type',mime); self.send_header('Content-Length',str(end-start+1))
        self.send_header('Accept-Ranges','bytes'); self.send_header('Cache-Control','no-store'); self.end_headers()
        try: self.wfile.write(data[start:end+1])
        except (BrokenPipeError,ConnectionResetError): pass

for port in [8765,8766]:
    server=http.server.ThreadingHTTPServer(('0.0.0.0',port),Handler)
    threading.Thread(target=server.serve_forever,daemon=True).start()
threading.Event().wait()
