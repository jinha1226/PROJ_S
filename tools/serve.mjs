import http from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root=path.resolve(fileURLToPath(new URL('../',import.meta.url)));
export function serve(port=4173) {
  const types={'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.css':'text/css','.json':'application/json'};
  const server=http.createServer(async(req,res)=>{
    try{
      const url=new URL(req.url,'http://localhost'),relative=decodeURIComponent(url.pathname==='/'?'/index.html':url.pathname);
      const filename=path.resolve(root,'.'+relative);
      if(!filename.startsWith(root+path.sep))throw new Error('Invalid path');
      const body=await readFile(filename);res.setHeader('Content-Type',types[path.extname(filename)]||'application/octet-stream');res.end(body);
    }catch{res.statusCode=404;res.end('Not found');}
  });
  return new Promise(resolve=>server.listen(port,'127.0.0.1',()=>resolve(server)));
}
if(process.argv[1]===fileURLToPath(import.meta.url)){await serve(Number(process.env.PORT)||4173);console.log('Last Ember: http://127.0.0.1:4173');}
