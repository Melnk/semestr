import {useEffect,useId,useRef,useState} from 'react';
import {X,Plus,Trash2} from 'lucide-react';
import {api,isLocalApp,type Data,type StudyRecord,type Subject,type Account,type Link} from '@semestr/api-client';
import {emptyData,labels,typed} from './utils';
import DebtSubjectField from './DebtSubjectField';
import TimeField from './TimeField';
export function Dialog({title,description,eyebrow='СЕМЕСТР',children,footer,onClose}:{title:string;description?:string;eyebrow?:string;children:React.ReactNode;footer?:React.ReactNode;onClose:()=>void}){
 const ref=useRef<HTMLDialogElement>(null);const heading=useRef<HTMLHeadingElement>(null);const id=useId();
 useEffect(()=>{const el=ref.current!;el.showModal();heading.current?.focus({preventScroll:true});return()=>el.close()},[]);
 return <dialog className="modal" ref={ref} aria-labelledby={id+'-title'} aria-describedby={description?id+'-description':undefined} onCancel={e=>{e.preventDefault();onClose()}} onClick={e=>{if(e.target===ref.current)onClose()}}>
  <header className="dialog-heading"><div><span className="eyebrow">{eyebrow}</span><h2 id={id+'-title'} ref={heading} tabIndex={-1}>{title}</h2>{description&&<p id={id+'-description'} className="dialog-description">{description}</p>}</div><button type="button" className="icon-button dialog-close" aria-label="Закрыть окно" onClick={onClose}><X size={20}/></button></header>
  <div className="dialog-body">{children}</div>
  {footer&&<div className="dialog-footer">{footer}</div>}
 </dialog>;
}
export default function Editor({kind,existing,subjectId,records,account,onClose,onSaved}:{kind:Data['kind'];existing?:StudyRecord;subjectId:string;records:StudyRecord[];account:Account;onClose:()=>void;onSaved:(message?:string,subjectId?:string)=>void}){
 const formId=useId();
 const inlineDebt=isLocalApp&&kind==='debt'&&!existing;
 const draftKey=`semestr:draft:${account.id}:${existing?.id||kind+':'+subjectId}`;
 const readDraft=()=>{try{return JSON.parse(localStorage.getItem(draftKey)||'null')}catch{return null}};
 const [restored]=useState(()=>!!readDraft());const[baseVersion,setBaseVersion]=useState<number|undefined>(()=>readDraft()?.baseVersion??existing?.version);const[data,setData]=useState<Data>(()=>readDraft()?.data||existing?.data||emptyData(kind,subjectId,account.profile.timezone,account.profile.weekOne));const[deleting,setDeleting]=useState(false);const[error,setError]=useState('');const[busy,setBusy]=useState(false);const[draftError,setDraftError]=useState(false);
 useEffect(()=>{if(error)document.getElementById(formId)?.querySelector('[role=alert]')?.scrollIntoView({block:'nearest'})},[error,formId]);
 const[subjectMode,setSubjectMode]=useState<'new'|'existing'>(()=>readDraft()?.subjectMode||(readDraft()?.data?.subjectId?'existing':'new'));
 const[subjectTitle,setSubjectTitle]=useState<string>(()=>readDraft()?.subjectTitle||'');
 useEffect(()=>{try{localStorage.setItem(draftKey,JSON.stringify({data,baseVersion,...(inlineDebt?{subjectMode,subjectTitle}:{})}))}catch{setDraftError(true)}},[data,draftKey,baseVersion,inlineDebt,subjectMode,subjectTitle]);
 const field=(key:string,value:unknown)=>setData(d=>({...d,[key]:value}) as Data);
 const value=(key:string)=>String((data as unknown as Record<string,unknown>)[key]??'');
 function input(label:string,key:string,type='text',required=false){return <label>{label}<input name={key} type={type} required={required} maxLength={type==='text'?300:undefined} value={value(key)} onChange={e=>field(key,e.target.value||(type==='date'?null:''))}/></label>}
 function area(label:string,key:string,placeholder='',rows=3){return <label>{label}<textarea name={key} placeholder={placeholder} rows={rows} maxLength={20000} value={value(key)} onChange={e=>field(key,e.target.value)}/></label>}
 function select(label:string,key:string,options:string[]){return <label>{label}<select name={key} value={value(key)} onChange={e=>field(key,e.target.value)}>{options.map(v=><option key={v} value={v}>{labels[v]||v}</option>)}</select></label>}
 async function save(e:React.FormEvent){
  e.preventDefault();if(busy)return;setBusy(true);setError('');
  try{
   let debtSubjectId:string|undefined;
   if(inlineDebt&&data.kind==='debt'&&subjectMode==='new'){
    const result=await api.createDebtWithSubject(data,subjectTitle);
    debtSubjectId=result.subject.id;
   }else{
    const saved=await api.save(data,existing?{...existing,version:baseVersion??existing.version}:undefined);
    if(!existing&&saved.data.kind==='debt')debtSubjectId=saved.data.subjectId;
   }
   try{localStorage.removeItem(draftKey)}catch{/* The record is already saved. */}
   onSaved(debtSubjectId?'Долг добавлен':undefined,debtSubjectId);onClose();
  }catch(e){setError((e as Error).message)}finally{setBusy(false)}
 }
 async function reloadLatest(){if(!existing)return;try{const latest=await api.request<StudyRecord>('/records/'+existing.id);setData(latest.data);setBaseVersion(latest.version);setError('')}catch(e){setError((e as Error).message)}}
 async function remove(){if(!existing)return;setBusy(true);setError('');try{await api.request('/records/'+existing.id+'?version='+(baseVersion??existing.version),'DELETE');try{localStorage.removeItem(draftKey)}catch{/* Server save already succeeded. */}onSaved('Запись удалена');onClose()}catch(e){setError((e as Error).message)}finally{setBusy(false)}}
 const links='links' in data?data.links:[];
 const names={subject:'Предмет',task:'Задание',debt:'Академический долг',lesson:'Занятие',note:'Заметка'};
 const linkedSubject=typed<Subject>(records,'subject').find(s=>s.id===value('subjectId'));
 function materials(){return <fieldset className="editor-materials"><legend>Ссылки и материалы</legend>{links.map((link,i)=><div className="link-fields" key={i}><input aria-label="Название ссылки" placeholder="Название материала" value={link.title} required onChange={e=>field('links',links.map((l,j)=>j===i?{...l,title:e.target.value}:l))}/><input type="url" aria-label="Адрес ссылки" placeholder="https://" value={link.url} required onChange={e=>field('links',links.map((l,j)=>j===i?{...l,url:e.target.value}:l))}/><button type="button" aria-label="Удалить ссылку" className="icon-button" onClick={()=>field('links',links.filter((_,j)=>j!==i))}><Trash2 size={16}/></button></div>)}<button type="button" className="text-button" onClick={()=>field('links',[...links,{title:'',url:''} as Link])}><Plus size={15}/> Добавить ссылку</button></fieldset>}
 function extra(title:string,children:React.ReactNode){return <details className="editor-details"><summary>{title}</summary><div>{children}</div></details>}
 function revealInvalid(e:React.FormEvent<HTMLFormElement>){let parent=(e.target as HTMLElement).parentElement;while(parent&&parent!==e.currentTarget){if(parent instanceof HTMLDetailsElement)parent.open=true;parent=parent.parentElement}}
 return <Dialog title={names[kind]} eyebrow={existing?'РЕДАКТИРОВАНИЕ':'НОВАЯ ЗАПИСЬ'} description={kind!=='subject'?(inlineDebt&&subjectMode==='new'?undefined:linkedSubject?.data.title):existing?'Преподаватель, условия сдачи и материалы.':'Начните с названия. Остальное можно заполнить позже.'} onClose={onClose} footer={<><span className="dialog-draft">{draftError?'Не удалось сохранить черновик. Не закрывайте окно.':'Черновик сохраняется на этом устройстве'}</span><div className="dialog-actions"><button type="button" className="outline" onClick={onClose}>Отмена</button><button type="submit" form={formId} className="primary" disabled={busy}>{busy?'Сохраняем…':inlineDebt?'Добавить долг':'Сохранить'}</button></div></>}>
 <form id={formId} onSubmit={save} onInvalidCapture={revealInvalid} className="editor-form">
 {restored&&<div className="info">Восстановлен черновик с этого устройства.</div>}
 {inlineDebt&&<DebtSubjectField subjects={typed<Subject>(records,'subject')} mode={subjectMode} title={subjectTitle} subjectId={value('subjectId')} onMode={setSubjectMode} onTitle={setSubjectTitle} onSelect={id=>field('subjectId',id)}/>}
 {kind!=='subject'&&!existing&&!inlineDebt&&<label>Предмет<select required name="subjectId" value={value('subjectId')} onChange={e=>field('subjectId',e.target.value)}><option value="">Выберите предмет</option>{typed<Subject>(records,'subject').map(s=><option key={s.id} value={s.id}>{s.data.title}</option>)}</select></label>}
 {(kind==='subject'||kind==='task')&&input('Название','title','text',true)}
 {kind==='subject'&&<>
  <div className="form-grid">{input('Преподаватель','teacher')}{input('Контакты преподавателя','contact')}{select('Аттестация','assessment',['unknown','exam','credit','graded_credit'])}{input('Семестр','semester')}</div>
  {area('Условия сдачи','requirements','Какие работы нужно выполнить и как их сдать')}{select('Статус','status',['studying','ready','closed'])}
  {extra('Описание и допуск',<>{area('Описание','description')}{area('Условия допуска','admission')}</>)}
  {extra('Онлайн-пара и материалы',<>{input('Ссылка на онлайн-пару','onlineUrl','url')}{materials()}</>)}
 </>}
 {kind==='task'&&<>
  <div className="form-grid"><label>Дедлайн<input name="deadline" type="datetime-local" value={data.kind==='task'&&data.deadline?new Date(new Date(data.deadline).getTime()-new Date(data.deadline).getTimezoneOffset()*60000).toISOString().slice(0,16):''} onChange={e=>field('deadline',e.target.value?new Date(e.target.value).toISOString():null)}/><span className="field-hint">В часовом поясе этого устройства</span></label>{select('Статус','status',['todo','in_progress','submitted','accepted','revision'])}</div>
  {area('Что нужно сделать','description','Условия задания, объём работы и формат сдачи')}
  {extra('Связи и результат',<><div className="form-grid">{(['debt','lesson'] as const).map(k=><label key={k}>{k==='debt'?'Связанный долг':'Связанное занятие'}<select name={k+'Id'} value={value(k+'Id')} onChange={e=>field(k+'Id',e.target.value||null)}><option value="">Не связан</option>{records.filter(r=>r.data.kind===k&&'subjectId'in r.data&&r.data.subjectId===value('subjectId')).map(r=><option key={r.id} value={r.id}>{r.data.kind==='debt'?labels[r.data.reason]:r.data.kind==='lesson'?`${r.data.startTime} · ${labels[r.data.type]}`:''}</option>)}</select></label>)}</div>{input('Ссылка на результат','resultUrl','url')}</>)}
  {extra('Заметки и материалы',<>{area('Заметки','notes')}{materials()}</>)}
 </>}
 {kind==='debt'&&<>
  <div className="form-grid">{select('Причина','reason',['difference','overdue','retake'])}{input('Срок сдачи','deadline','date')}</div>
  {input('Следующий шаг','nextStep')}{area('Что нужно сдать','requirements','Например: две практические работы и защита проекта')}
  <div className={value('status')==='closed'?'form-grid':undefined}>{select('Статус','status',['clarify','working','review','ready','closed'])}{value('status')==='closed'&&input('Дата закрытия','closedAt','date',true)}</div>
  {value('status')==='closed'&&area('Подтверждение результата','confirmation','Например: оценка внесена в ведомость')}
  {value('status')!=='closed'&&value('closedAt')&&<button type="button" className="text-button" onClick={()=>field('closedAt',null)}>Очистить дату закрытия для возобновления</button>}
  {extra('Преподаватель и заметки',<>{input('Ответственный преподаватель','teacher')}{area('Заметки','notes')}</>)}
 </>}
 {kind==='lesson'&&<>
  <div className="form-grid"><label>День недели<select name="weekday" value={value('weekday')} onChange={e=>field('weekday',Number(e.target.value))}>{['Понедельник','Вторник','Среда','Четверг','Пятница','Суббота','Воскресенье'].map((d,i)=><option value={i+1} key={d}>{d}</option>)}</select></label>{select('Тип','type',['lecture','practice','lab'])}<TimeField label="Начало" value={value('startTime')} onChange={v=>field('startTime',v)}/><TimeField label="Окончание" value={value('endTime')} onChange={v=>field('endTime',v)}/></div>
  <p className="field-hint lesson-overnight-hint">Если окончание раньше начала, пара закончится на следующий день.</p>
  <section className="editor-section"><h3>Повторение</h3><div className="form-grid">{input('С какой даты','validFrom','date',true)}{input('По какую дату','validUntil','date',true)}{select('Недели','parity',['all','even','odd'])}{input('Начало учебной недели № 1','weekOne','date',true)}</div></section>
  {extra('Место, подключение и часовой пояс',<>{input('Аудитория / место','room')}{input('Ссылка на пару','onlineUrl','url')}{input('Часовой пояс занятия','timezone','text',true)}</>)}
 </>}
 {kind==='note'&&area('Текст заметки','text','Что важно запомнить по этому предмету',8)}
 {error&&<div className="error" role="alert">{error}{existing&&<button type="button" className="text-button" onClick={()=>void reloadLatest()}>Отбросить черновик и загрузить актуальную версию</button>}</div>}
 {existing&&<div className="delete-editor">{deleting?<><p className="muted">Удаление нельзя отменить. Связанные записи нужно удалить отдельно.</p><div className="button-row"><button type="button" className="danger-button" disabled={busy} onClick={()=>void remove()}>Подтвердить удаление</button><button type="button" className="text-button" onClick={()=>setDeleting(false)}>Отмена</button></div></>:<button type="button" className="text-button danger" onClick={()=>setDeleting(true)}><Trash2 size={14}/> Удалить запись</button>}</div>}
 </form></Dialog>
}
