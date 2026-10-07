import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {createRequire} from 'node:module';
import {dirname,join,resolve} from 'node:path';

const requireWeb=createRequire(resolve('apps/web/package.json'));
const requireReactDOM=createRequire(requireWeb.resolve('react-dom/package.json'));
const names=['react','react-dom','scheduler','lucide-react'];
const notices=names.map(name=>{
 const packageFile=(name==='scheduler'?requireReactDOM:requireWeb).resolve(`${name}/package.json`);
 const metadata=JSON.parse(readFileSync(packageFile,'utf8'));
 const license=['LICENSE','LICENSE.md','LICENSE.txt'].map(file=>join(dirname(packageFile),file)).find(existsSync);
 if(!license)throw new Error(`License missing for ${name}`);
 return `${name} ${metadata.version}\n${'='.repeat(60)}\n${readFileSync(license,'utf8')}`;
});
writeFileSync(process.argv[2]??'dist/THIRD_PARTY_NOTICES.txt','Third-party software bundled with Semestr\n\n'+notices.join('\n\n'));
