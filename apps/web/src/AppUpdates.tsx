import {useCallback,useEffect,useState} from 'react';
import {ArrowUpRight,Download,RefreshCw} from 'lucide-react';
import {nativeAction} from '@semestr/api-client';

type UpdateStatus={currentVersion:string;automatic:boolean;lastCheckedAt:string|null;checking:boolean;downloading:boolean;availableVersion:string|null;releaseURL:string|null;installerReady:boolean;error:string};

export function useAppUpdates(enabled:boolean){
 const[status,setStatus]=useState<UpdateStatus|null>(null);
 const[pending,setPending]=useState(false);
 const[error,setError]=useState('');
 const refresh=useCallback(async()=>{
  if(!enabled)return;
  try{setStatus(await nativeAction<UpdateStatus>('updateStatus'));setError('')}catch(e){setError((e as Error).message)}
 },[enabled]);
 const command=useCallback(async(action:string,parameters:Record<string,unknown>={})=>{
  if(!enabled)return;setPending(true);setError('');
  try{setStatus(await nativeAction<UpdateStatus>(action,parameters))}catch(e){setError((e as Error).message)}finally{setPending(false)}
 },[enabled]);
 useEffect(()=>{
  if(!enabled){setStatus(null);return}
  void refresh();
  const changed=()=>void refresh();
  window.addEventListener('semestr:update-status',changed);window.addEventListener('focus',changed);
  return()=>{window.removeEventListener('semestr:update-status',changed);window.removeEventListener('focus',changed)};
 },[enabled,refresh]);
 return {status,error:error||status?.error||'',busy:pending||!!status?.checking||!!status?.downloading,
  check:useCallback(()=>command('updateCheck'),[command]),
  download:useCallback(()=>command('updateDownload'),[command]),
  automatic:(value:boolean)=>command('updatePreferences',{automatic:value})};
}
export type AppUpdates=ReturnType<typeof useAppUpdates>;

function UpdateButton({updates}:{updates:AppUpdates}){
 const{status,busy,download}=updates;
 return <button className="primary update-download" disabled={busy} onClick={()=>void download()}>
  {status?.downloading?<RefreshCw size={16} className="spin"/>:<Download size={16}/>}
  {status?.downloading?'Скачиваем…':status?.installerReady?'Открыть установщик':'Обновить'}
 </button>;
}

export function UpdateBanner({updates,onDetails}:{updates:AppUpdates;onDetails:()=>void}){
 const{status,error}=updates;
 if(!status?.availableVersion)return null;
 return <div className="update-banner" role="status">
  <div><strong>Доступен «Семестр» {status.availableVersion}</strong><span>{status.installerReady?'Установщик открыт. Замените приложение в «Программах».':error?'Обновление не завершено. Подробности в настройках.':'Новая версия готова к установке.'}</span></div>
  <div className="button-row"><button className="text-button" onClick={onDetails}>Подробнее</button><UpdateButton updates={updates}/></div>
 </div>;
}

export function UpdateSettings({updates}:{updates:AppUpdates}){
 const{status,error,busy,check,automatic}=updates;
 return <section className="update-settings" aria-labelledby="updates-heading">
  <h2 id="updates-heading"><RefreshCw size={22}/> Обновления приложения</h2>
  {status?<>
   <p className="muted">Установлена версия {status.currentVersion}.</p>
   <label className="checkbox-label update-automatic"><input id="update-automatic" type="checkbox" role="switch" checked={status.automatic} disabled={busy} onChange={e=>void automatic(e.target.checked)}/>Проверять обновления каждый день</label>
   <p className="muted small">Проверяем при открытом приложении и после возвращения к нему. Обновление скачивается только по вашему нажатию.</p>
   <div className="update-summary" role="status">
    {status.checking?'Проверяем GitHub…':status.availableVersion?`Доступна новая версия ${status.availableVersion}.`:status.lastCheckedAt&&!error?'У вас последняя версия.':'Можно проверить наличие новой версии на GitHub.'}
   </div>
   <div className="button-row">
    <button className="outline update-check" disabled={busy} onClick={()=>void check()}><RefreshCw size={16} className={status.checking?'spin':''}/>{status.checking?'Проверяем…':'Проверить обновление'}</button>
    {status.availableVersion&&<UpdateButton updates={updates}/>}
    {status.releaseURL&&<a className="text-button" href={status.releaseURL} target="_blank" rel="noreferrer">Что нового <ArrowUpRight size={14}/></a>}
   </div>
   {status.availableVersion&&<p className="update-instructions">{status.installerReady?'Установщик открыт.':'По кнопке «Обновить» скачаем и откроем установщик.'} Закройте «Семестр», перенесите новую версию в «Программы» с заменой и откройте её. Ваши данные и настройки сохранятся.</p>}
   {status.lastCheckedAt&&<p className="muted small update-last-check">Последняя успешная проверка: {new Intl.DateTimeFormat('ru',{dateStyle:'medium',timeStyle:'short'}).format(new Date(status.lastCheckedAt))}.</p>}
  </>:!error&&<p className="muted">Загружаем настройки обновлений…</p>}
  {error&&<div className="error" role="alert">{error}{!status&&<button className="text-button" disabled={busy} onClick={()=>void check()}>Повторить</button>}</div>}
 </section>;
}
