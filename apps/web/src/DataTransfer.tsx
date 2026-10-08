import {useRef,useState} from 'react';
import {ArrowRight,Download,Upload} from 'lucide-react';
import {api,isLocalApp,nativeAction,type Account,type Bundle} from '@semestr/api-client';
import {FileSummary,saveNativeFile,type ImportedFile,type TransferFile} from './TransferFiles';

export default function DataTransfer({demo,onApplied,notify}:{demo:boolean;onApplied:(account:Account)=>void;notify:(message:string)=>void}){
 const[busy,setBusy]=useState(false);const[error,setError]=useState('');
 const[bundle,setBundle]=useState<Bundle|null>(null);const[preview,setPreview]=useState<Record<string,number>|null>(null);
 const[file,setFile]=useState<Pick<TransferFile,'name'|'size'>&{folder?:string}|null>(null);
 const[revision,setRevision]=useState(0);const[mode,setMode]=useState('add');const[confirmed,setConfirmed]=useState(false);
 const input=useRef<HTMLInputElement>(null);
 function clear(){setBundle(null);setPreview(null);setFile(null);setConfirmed(false);setError('')}
 async function saveFile(){
  if(demo){notify('Экспорт доступен для данных вашего аккаунта.');return}
  setBusy(true);setError('');
  try{
   if(isLocalApp){await saveNativeFile();return}
   const data=await api.request<Bundle>('/export');
   const url=URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'}));
   const link=document.createElement('a');link.href=url;link.download='semestr-export.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
   notify('Файл передан в загрузки браузера.');
  }catch(e){setError((e as Error).message)}finally{setBusy(false)}
 }
 async function prepare(data:Bundle,selected:Pick<TransferFile,'name'|'size'>&{folder?:string}){
  const session=await api.session();
  const counts=await api.request<Record<string,number>>('/import/preview','POST',data);
  setRevision(session.account.revision);setBundle(data);setPreview(counts);setFile(selected);setMode('add');setConfirmed(false);
 }
 async function chooseFile(){
  if(demo){notify('Импорт доступен для данных вашего аккаунта.');return}
  if(!isLocalApp){input.current?.click();return}
  setBusy(true);setError('');
  try{const selected=await nativeAction<ImportedFile<Bundle>|null>('import');if(selected)await prepare(selected.bundle,selected.file)}
  catch(e){clear();setError((e as Error).message)}finally{setBusy(false)}
 }
 async function upload(selected?:File){
  if(!selected)return;setBusy(true);setError('');
  try{
   if(selected.size>5_000_000)throw new Error('Файл должен быть меньше 5 МБ.');
   let data:Bundle;try{data=JSON.parse(await selected.text())}catch{throw new Error('Не удалось прочитать JSON. Выберите файл, сохранённый в «Семестре».')}
   await prepare(data,{name:selected.name,size:selected.size});
  }catch(e){clear();setError((e as Error).message)}finally{setBusy(false)}
 }
 async function apply(){
  if(!bundle||!preview)return;setBusy(true);setError('');
  try{
   await api.request('/import','POST',{bundle,mode,expectedRevision:revision,confirmed});
   clear();onApplied((await api.session()).account);notify('Данные импортированы целиком');
  }catch(e){setError((e as Error).message)}finally{setBusy(false)}
 }
 return <section className="data-transfer" aria-labelledby="data-transfer-heading">
  <h2 id="data-transfer-heading">Ваши данные — с вами</h2>
  <p className="muted">Предметы, задания, долги, заметки и расписание — в одном файле для резервной копии или переноса.</p>
  <div className="transfer-choices">
   <div className="transfer-choice"><h3>Сохранить копию</h3><p>Выберите, куда сохранить файл с учебными данными.</p><button className="outline export-data" disabled={busy} onClick={()=>void saveFile()}><Download size={17}/>Сохранить данные в файл…</button></div>
   <div className="transfer-choice"><h3>Импортировать из файла</h3><p>Выберите ранее сохранённый JSON-файл. Сначала покажем, что внутри.</p><button className="outline choose-data-file" disabled={busy} onClick={()=>void chooseFile()}><Upload size={17}/>{file?'Выбрать другой файл…':'Выбрать файл…'}</button>{!isLocalApp&&<input ref={input} type="file" style={{display:'none'}} accept=".json,application/json" onChange={e=>{void upload(e.target.files?.[0]);e.target.value=''}}/>}</div>
  </div>
  {busy&&<p className="muted small" role="status">Подготавливаем файл…</p>}
  {preview&&bundle&&file&&<div className="import-preview data-preview">
   <h3>Файл проверен</h3><FileSummary file={file}/>
   <p>Предметов: {preview.subjects} · Заданий: {preview.tasks} · Долгов: {preview.debts}<br/>Занятий: {preview.lessons} · Заметок: {preview.notes} · Исключений: {preview.exceptions}</p>
   <label>Как импортировать<select disabled={busy} value={mode} onChange={e=>{setMode(e.target.value);setConfirmed(false)}}><option value="add">Добавить к существующим</option><option value="replace">Заменить все учебные данные и профиль</option></select></label>
   {mode==='replace'&&<label className="checkbox-label"><input type="checkbox" disabled={busy} checked={confirmed} onChange={e=>setConfirmed(e.target.checked)}/>Я понимаю, что текущие данные будут удалены и заменены содержимым файла.</label>}
   <div className="button-row"><button className="primary" disabled={busy||(mode==='replace'&&!confirmed)} onClick={()=>void apply()}>Импортировать <ArrowRight size={16}/></button><button className="text-button" disabled={busy} onClick={clear}>Отмена</button></div>
  </div>}
  {error&&<div className="error" role="alert">{error}</div>}
 </section>;
}
