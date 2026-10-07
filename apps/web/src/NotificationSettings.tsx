import {useEffect,useState} from 'react';
import {Bell,Check,ExternalLink} from 'lucide-react';
import {api,nativeAction,type NotificationPreferences,type NotificationStatus} from '@semestr/api-client';
import {labels} from './utils';
import TimeField from './TimeField';

export default function NotificationSettings({version,timezone,notify}:{version:number;timezone:string;notify:(message:string)=>void}){
 const [preferences,setPreferences]=useState<NotificationPreferences|null>(null);
 const [status,setStatus]=useState<NotificationStatus|null>(null);
 const [busy,setBusy]=useState(false);
 const [error,setError]=useState('');
 async function load(){
  try {
   const [preferences,status]=await Promise.all([api.request<NotificationPreferences>('/notifications'),nativeAction<NotificationStatus>('notificationStatus')]);
   setPreferences(preferences);setStatus(status);setError('');
  }catch(e){setError((e as Error).message)}
 }
 useEffect(()=>{void load()},[version]);
 useEffect(()=>{
  const refresh=()=>{if(document.visibilityState==='visible')void nativeAction<NotificationStatus>('notificationStatus').then(setStatus).catch(e=>setError(e.message))};
  document.addEventListener('visibilitychange',refresh);window.addEventListener('focus',refresh);
  return()=>{document.removeEventListener('visibilitychange',refresh);window.removeEventListener('focus',refresh)};
 },[]);
 function field<K extends keyof NotificationPreferences>(key:K,value:NotificationPreferences[K]){setPreferences(p=>p?{...p,[key]:value}:p)}
 async function save(e:React.FormEvent){
  e.preventDefault();if(!preferences||busy)return;setBusy(true);setError('');
  try {
   if(preferences.enabled){
    const current=await nativeAction<NotificationStatus>('notificationStatus');
    if(current.authorization==='notDetermined')await nativeAction('notificationPermission');
   }
   // Turning everything off must also work if an unfinished numeric draft is invalid.
   const saved=preferences.enabled?preferences:{...await api.request<NotificationPreferences>('/notifications'),enabled:false};
   setPreferences(await api.request<NotificationPreferences>('/notifications','PUT',saved));
   const next=await nativeAction<NotificationStatus>('notificationStatus');setStatus(next);
   if(next.error)setError(next.error);
   else notify(preferences.enabled?'Настройки уведомлений сохранены':'Уведомления отключены');
  }catch(e){setError((e as Error).message)}finally{setBusy(false)}
 }
 async function authorize(){setBusy(true);setError('');try{setStatus(await nativeAction<NotificationStatus>('notificationPermission'))}catch(e){setError((e as Error).message)}finally{setBusy(false)}}
 const permitted=status&&['authorized','provisional'].includes(status.authorization);
 return <section className="notification-settings" aria-labelledby="notification-heading">
  <h2 id="notification-heading"><Bell size={22}/> Уведомления</h2>
  <p className="muted">Выберите, о каких парах и сроках напоминать. Изменения применяются после сохранения.</p>
  {preferences?<form onSubmit={save}>
   <label className="notification-master checkbox-label"><input id="notification-enabled" type="checkbox" role="switch" checked={preferences.enabled} disabled={busy} onChange={e=>field('enabled',e.target.checked)}/><span>Включить уведомления</span></label>
   <fieldset className="notification-options" disabled={!preferences.enabled||busy}>
    <div className="notification-group">
     <label className="checkbox-label"><input id="notification-lessons" type="checkbox" checked={preferences.lessonsEnabled} onChange={e=>field('lessonsEnabled',e.target.checked)}/>О занятиях</label>
     <fieldset disabled={!preferences.lessonsEnabled}>
      <legend>На какие пары напоминать</legend>
      <div className="notification-choices">{['practice','lecture','lab'].map(type=><label key={type} className="checkbox-label"><input type="checkbox" data-lesson-type={type} checked={preferences.lessonTypes.includes(type)} onChange={e=>field('lessonTypes',e.target.checked?[...preferences.lessonTypes,type]:preferences.lessonTypes.filter(t=>t!==type))}/>{labels[type]}</label>)}</div>
      <label>За сколько минут до начала<input id="notification-lesson-minutes" type="number" min={1} max={120} required value={preferences.lessonMinutes} onChange={e=>field('lessonMinutes',Number(e.target.value))}/></label>
     </fieldset>
    </div>
    <div className="notification-group">
     <label className="checkbox-label"><input id="notification-deadlines" type="checkbox" checked={preferences.deadlinesEnabled} onChange={e=>field('deadlinesEnabled',e.target.checked)}/>О дедлайнах заданий и долгов</label>
     <fieldset disabled={!preferences.deadlinesEnabled}>
      <legend>Можно выбрать несколько напоминаний</legend>
      <div className="notification-choices">{([[15,'За 15 минут'],[60,'За час'],[180,'За 3 часа'],[1440,'За сутки'],[2880,'За 2 суток']] as const).map(([minutes,label])=><label key={minutes} className="checkbox-label"><input type="checkbox" data-deadline-minutes={minutes} checked={preferences.deadlineMinutes.includes(minutes)} onChange={e=>field('deadlineMinutes',e.target.checked?[...preferences.deadlineMinutes,minutes]:preferences.deadlineMinutes.filter(m=>m!==minutes))}/>{label}</label>)}</div>
      <div className="notification-debt-time"><TimeField label="Время срока долга, если указана только дата" value={preferences.debtTime} onChange={v=>field('debtTime',v)}/></div>
      <p className="muted small">Для долга с датой без времени используем этот час в поясе {timezone}. У заданий учитываем точное время дедлайна. Сданные и принятые задания, закрытые долги и предметы не беспокоят.</p>
     </fieldset>
    </div>
    <label className="checkbox-label"><input id="notification-sound" type="checkbox" checked={preferences.sound} onChange={e=>field('sound',e.target.checked)}/>Со звуком</label>
   </fieldset>
   <button className="primary" disabled={busy}>{busy?'Сохраняем…':'Сохранить уведомления'} <Check size={16}/></button>
  </form>:!error&&<p className="muted">Загружаем настройки…</p>}
  {preferences?.enabled&&status&&<div className="notification-status" role="status">
   {status.authorization==='denied'?<><p>macOS не разрешает уведомления «Семестра». Откройте «Системные настройки → Уведомления → Семестр» и включите их.</p><button className="text-button" disabled={busy} onClick={()=>void nativeAction('notificationSystemSettings').catch(e=>setError(e.message))}>Открыть системные настройки <ExternalLink size={14}/></button></>:status.authorization==='notDetermined'?<><p>Разрешите «Семестру» показывать уведомления на этом Mac.</p><button className="outline" disabled={busy} onClick={()=>void authorize()}>Разрешить уведомления</button></>:permitted&&<>
    <p>{status.pendingCount?`Запланировано напоминаний: ${status.pendingCount}.`:'В подготовленном периоде пока нет подходящих пар и дедлайнов.'}</p>
    {status.coveredUntil&&<p>{status.pendingCount>0&&'Запланированные напоминания приходят и при закрытом приложении. '}Расписание подготовлено до {new Intl.DateTimeFormat('ru',{dateStyle:'medium',timeStyle:'short',timeZone:timezone}).format(new Date(status.coveredUntil))}. Откройте «Семестр» до этой даты, чтобы продлить его.</p>}
    <p className="muted small">Показ баннеров и звук также зависят от настроек macOS и режима «Фокусирование».</p>
   </>}
  </div>}
  {(error||status?.error)&&<div className="error" role="alert">{error||status?.error}<button className="text-button" onClick={()=>void load()}>Повторить</button></div>}
 </section>;
}
