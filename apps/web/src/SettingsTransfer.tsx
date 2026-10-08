import {useState} from 'react';
import {ArrowRight,Download,Upload} from 'lucide-react';
import {api,nativeAction,type SettingsApplied,type SettingsBundle,type SettingsPreview} from '@semestr/api-client';
import {FileSummary,saveNativeFile,type ImportedFile,type TransferFile} from './TransferFiles';

export default function SettingsTransfer({onApplied,notify}:{onApplied:(result:SettingsApplied)=>void;notify:(message:string)=>void}){
 const[busy,setBusy]=useState(false);
 const[error,setError]=useState('');
 const[preview,setPreview]=useState<SettingsPreview|null>(null);
 const[file,setFile]=useState<TransferFile|null>(null);

 async function saveFile(){
  setBusy(true);setError('');
  try{await saveNativeFile(true)}
  catch(e){setError((e as Error).message)}finally{setBusy(false)}
 }
 async function chooseFile(){
  setBusy(true);setError('');
  try{
   const selected=await nativeAction<ImportedFile<SettingsBundle>|null>('importSettings');
   if(selected){setPreview(await api.request<SettingsPreview>('/settings/preview','POST',selected.bundle));setFile(selected.file)}
  }catch(e){setPreview(null);setFile(null);setError((e as Error).message)}finally{setBusy(false)}
 }
 async function apply(){
  if(!preview)return;
  setBusy(true);setError('');
  try{
   const result=await api.request<SettingsApplied>('/settings/import','POST',preview);
   setPreview(null);setFile(null);onApplied(result);notify('Настройки перенесены. Учебные записи сохранены.');
  }catch(e){setError((e as Error).message)}finally{setBusy(false)}
 }

 return <section className="settings-transfer" aria-labelledby="settings-transfer-heading">
  <h2 id="settings-transfer-heading">Перенос настроек</h2>
  <p className="muted">Сохраните настройки и перенесите файл на другой Mac или в другую учётную запись.</p>
  <p className="muted small">В файл входят сохранённый профиль, семестр, часовой пояс, начало учебной недели, тема оформления и настройки уведомлений. Сначала сохраните изменения в профиле выше.</p>
  <div className="transfer-choices">
   <div className="transfer-choice"><h3>Сохранить настройки</h3><p>Выберите папку для файла, который хотите перенести.</p><button className="outline" disabled={busy} onClick={()=>void saveFile()}><Download size={17}/> Сохранить настройки в файл…</button></div>
   <div className="transfer-choice"><h3>Загрузить настройки</h3><p>Выберите JSON-файл настроек. Учебные записи останутся на месте.</p><button className="outline choose-settings-file" disabled={busy} onClick={()=>void chooseFile()}><Upload size={17}/>{file?'Выбрать другой файл…':'Выбрать файл настроек…'}</button></div>
  </div>
  {busy&&<p className="muted small" role="status">Подготавливаем файл…</p>}
  {preview&&<div className="import-preview settings-preview">
   <h3>Настройки из файла</h3>
   {file&&<FileSummary file={file}/>}
   <dl className="facts">
    {([['name','Имя'],['university','Университет'],['direction','Направление'],['group','Группа'],['semester','Семестр'],['timezone','Часовой пояс'],['weekOne','Начало учебной недели № 1']] as const).map(([key,label])=><div key={key}><dt>{label}</dt><dd>{preview.bundle.profile[key]||'Не указано'}</dd></div>)}
    {preview.bundle.notifications&&<div><dt>Уведомления</dt><dd>{preview.bundle.notifications.enabled?'Включены':'Отключены'}. Разрешение macOS на этом компьютере настраивается отдельно.</dd></div>}
    <div><dt>Тема</dt><dd>{preview.bundle.appearance.theme==='dark'?'Тёмная':'Светлая'}</dd></div>
   </dl>
   <p>Эти значения заменят текущий профиль, оформление и настройки уведомлений из файла. Предметы, задания, долги, заметки и расписание на этом Mac сохранятся.</p>
   <div className="button-row">
    <button className="primary" disabled={busy} onClick={()=>void apply()}>Применить настройки <ArrowRight size={16}/></button>
    <button className="text-button" disabled={busy} onClick={()=>{setPreview(null);setFile(null);setError('')}}>Отмена</button>
   </div>
  </div>}
  {error&&<div className="error" role="alert">{error}</div>}
 </section>
}
