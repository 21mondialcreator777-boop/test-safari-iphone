"""Mirror only the public site on runner localhost; no deployment, no prospect data.
Candidate runtime modules are workflow input, never committed or logged.
"""
import base64,hashlib,http.server,json,os,pathlib,re,threading,urllib.request
from urllib.parse import urlsplit
patches=json.loads(base64.b64decode(os.environ['CANDIDATE_B64']))
for name,code in patches.items():
    print(name,hashlib.sha256(code.encode()).hexdigest(),flush=True)
cache=pathlib.Path('cache-scroll');cache.mkdir(exist_ok=True)
out=pathlib.Path('sortie-scroll');out.mkdir(exist_ok=True)
locks={}; lock=threading.Lock()
host_js=b"""
let settled=0;
const navigation=setInterval(()=>{
 const buttons=[...document.querySelectorAll('button')];
 buttons.find(b=>b.textContent.trim()==='Refuser')?.click();
 if(document.querySelector('iframe')){if(++settled>15)clearInterval(navigation);return;}
 buttons.find(b=>b.textContent.trim()==='Prestations')?.click();
},1000);
setTimeout(()=>clearInterval(navigation),45000);
"""
probe_js=b"""
const counts={pointerdown:0,pointermove:0,touchstart:0,touchmove:0,scroll:0};
for(const name of Object.keys(counts))addEventListener(name,()=>counts[name]++,{passive:true});
const tiny=document.createElement('canvas');tiny.width=24;tiny.height=16;
const ctx=tiny.getContext('2d',{willReadFrequently:true});
let tick=0;
setInterval(()=>{
 const film=window.PIFILM,canvas=document.getElementById('cv');if(!film||!canvas)return;
 let hash=2166136261;
 try{ctx.drawImage(canvas,0,0,24,16);const pixels=ctx.getImageData(0,0,24,16).data;for(const p of pixels)hash=Math.imul(hash^p,16777619)>>>0;}catch{}
 const record={tick:++tick,at:Date.now(),scrollY,counts:{...counts},hidden:document.hidden,hash,diagnostic:film.diagnostic()};
 fetch('/__scroll-proof',{method:'POST',body:JSON.stringify(record)}).catch(()=>{});
},200);
"""
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_POST(self):
        if self.path!='/__scroll-proof':self.send_error(405);return
        row=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))))
        with open(out/f'proof-{self.server.server_port}.ndjson','a') as f:f.write(json.dumps(row)+'\n')
        self.send_response(204);self.end_headers()
    def do_GET(self):
        route=urlsplit(self.path).path;fixed=self.server.server_port==8766
        if route=='/__host-scroll.js':body=host_js;mime='text/javascript'
        elif route=='/__probe-scroll.js':body=probe_js;mime='text/javascript'
        elif fixed and route in patches:body=patches[route].encode();mime='text/javascript'
        else:
            key=hashlib.sha256(self.path.encode()).hexdigest()
            with lock:mutex=locks.setdefault(key,threading.Lock())
            with mutex:
                file=cache/key;meta=cache/(key+'.json')
                if not meta.exists():
                    try:
                        with urllib.request.urlopen('https://parisimmo.re'+self.path,timeout=90) as r:
                            data=r.read();content=r.headers.get('Content-Type','application/octet-stream')
                        file.write_bytes(data);meta.write_text(json.dumps({'mime':content}))
                    except Exception as error:
                        print(route,str(error),flush=True);self.send_error(502);return
                body=file.read_bytes();mime=json.loads(meta.read_text())['mime']
            if 'text/html' in mime:
                if route in ['/prestations/index.html','/prestations/']:
                    if fixed:
                        def maps(match):
                            mapping=json.loads(match[1]);mapping.setdefault('imports',{}).update({'./js/data.js':'./js/data.js?v=20261101-scroll','./js/film.js':'./js/film.js?v=20261101-scroll'})
                            return '<script type="importmap">'+json.dumps(mapping)+'</script>'
                        body=re.sub(r'<script type="importmap">(.*?)</script>',maps,body.decode(),flags=re.S).encode()
                    body=body.replace(b'</body>',b'<script src="/__probe-scroll.js"></script></body>')
                elif route=='/':body=body.replace(b'</body>',b'<script src="/__host-scroll.js"></script></body>')
        total=len(body);start=0;end=total-1
        if self.headers.get('Range'):
            match=re.fullmatch(r'bytes=(\d+)-(\d*)',self.headers['Range'])
            if not match:self.send_error(416);return
            start=int(match[1]);end=min(end,int(match[2])) if match[2] else end
            if start>end:self.send_error(416);return
            self.send_response(206);self.send_header('Content-Range',f'bytes {start}-{end}/{total}')
        else:self.send_response(200)
        self.send_header('Content-Type',mime);self.send_header('Content-Length',str(end-start+1));self.send_header('Accept-Ranges','bytes');self.end_headers()
        try:self.wfile.write(body[start:end+1])
        except (BrokenPipeError,ConnectionResetError):pass
for port in [8765,8766]:
    server=http.server.ThreadingHTTPServer(('0.0.0.0',port),Handler)
    threading.Thread(target=server.serve_forever,daemon=True).start()
threading.Event().wait()
