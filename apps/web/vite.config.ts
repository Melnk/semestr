import {defineConfig} from 'vite';
import react from '@vitejs/plugin-react';
export default defineConfig(({mode})=>({
 base:'./',
 plugins:[react(),...(mode==='desktop'?[{
  name:'macos-local-resources',
  transformIndexHtml(html:string){return html.replace(/type="module" crossorigin/g,'defer').replace(/ crossorigin/g,'')}
 }]:[])],
 build:mode==='desktop'?{rollupOptions:{output:{format:'iife',inlineDynamicImports:true}}}:undefined,
 server:{port:5173,strictPort:true,proxy:{'/api':'http://127.0.0.1:8080','/v3':'http://127.0.0.1:8080'}}
}));
