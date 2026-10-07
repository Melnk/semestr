import {useState} from 'react';
import {ArrowRight,Download,Upload} from 'lucide-react';
import {api,nativeAction,type SettingsApplied,type SettingsBundle,type SettingsPreview} from '@semestr/api-client';

export default function SettingsTransfer({onApplied,notify}:{onApplied:(result:SettingsApplied)=>void;notify:(message:string)=>void}){
 const[busy,setBusy]=useState(false);
 const[error,setError]=useState('');
 const[preview,setPreview]=useState<SettingsPreview|null>(null);

 async function saveFile(){
  setBusy(true);setError('');
  try{const result=await nativeAction<{saved:boolean}>('exportSettings');if(result.saved)notify('Файл настроек сохранён. Его можно перенести на другой Mac.')}
  catch(e){setError((e as Error).message)}finally{setBusy(false)}
 }
 async function chooseFile(){
  setBusy(true);setError('');setPreview(null);
  try{
   const bundle=await nativeAction<SettingsBundle|null>('importSettings');
   if(bundle)setPreview(await api.request<SettingsPreview>('/settings/preview','POST',bundle));
  }catch(e){setError((e as Error).message)}finally{setBusy(false)}
 }
 async function apply(){
  if(!preview)return;
  setBusy(true);setError('');
  try{
   const result=await api.request<SettingsApplied>('/settings/import','POST',preview);
   setPreview(null);onApplied(result);notify('Настройки перенесены. Учебные записи сохранены.');
  }catch(e){setError((e as Error).message)}finally{setBusy(false)}
 }

 return <section className="settings-transfer" aria-labelledby="settings-transfer-heading">
  <h2 id="settings-transfer-heading">Перенос настроек</h2>
  <p className="muted">Сохраните файл и передайте его на другой Mac. Там откройте этот раздел в «Семестре» под нужной учётной записью и загрузите файл.</p>
  <p className="muted small">В файл входят сохранённый профиль, семестр, часовой пояс, начало учебной недели тема оформления и настройки уведомлений. Сначала сохраните изменения в профиле выше.</p>
  <div className="button-row">
   <button className="outline" disabled={busy} onClick={()=>void saveFile()}><Download size={17}/> Сохранить настройки в файл</button>
   <button className="outline" disabled={busy} onClick={()=>void chooseFile()}><Upload size={17}/> Загрузить настройки из файла</button>
  </div>
  {preview&&<div className="import-preview settings-preview">
   <h3>Настройки из файла</h3>
   <dl className="facts">
    {([['name','Имя'],['university','Университет'],['direction','Направление'],['group','Группа'],['semester','Семестр'],['timezone','Часовой пояс'],['weekOne','Начало учебной недели № 1']] as const).map(([key,label])=><div key={key}><dt>{label}</dt><dd>{preview.bundle.profile[key]||'Не указано'}</dd></div>)}
    {preview.bundle.notifications&&<div><dt>Уведомления</dt><dd>{preview.bundle.notifications.enabled?'Включены':'Отключены'}. Разрешение macOS на этом компьютере настраивается отдельно.</dd></div>}
    <div><dt>Тема</dt><dd>{preview.bundle.appearance.theme==='dark'?'Тёмная':'Светлая'}</dd></div>
   </dl>
   <p>Эти значения заменят текущий профиль, оформление и настройки уведомлений из файла. Предметы, задания, долги, заметки и расписание на этом Mac сохранятся.</p>
   <div className="button-row">
    <button className="primary" disabled={busy} onClick={()=>void apply()}>Применить настройки <ArrowRight size={16}/></button>
    <button className="text-button" disabled={busy} onClick={()=>{setPreview(null);setError('')}}>Отмена</button>
   </div>
  </div>}
  {error&&<div className="error" role="alert">{error}</div>}
 </section>
}
