import {useState} from 'react';
import {ArrowUpDown,Check,ChevronRight,Clock,FileText,Plus} from 'lucide-react';
import type {StudyRecord,Subject,Task} from '@semestr/api-client';
import {activeTask,dateLabel,labels} from './utils';

type Filter='all'|'open'|'accepted';

export default function Assignments({tasks,subjects,search,timezone,onAdd,onEdit}:{
 tasks:StudyRecord<Task>[];
 subjects:StudyRecord<Subject>[];
 search:string;
 timezone:string;
 onAdd:()=>void;
 onEdit:(task:StudyRecord<Task>)=>void;
}){
 const[filter,setFilter]=useState<Filter>('all');
 const subjectNames=new Map(subjects.map(s=>[s.id,s.data.title]));
 const query=search.trim().toLocaleLowerCase('ru');
 const visible=tasks.filter(t=>(filter==='all'||(filter==='open'?activeTask(t):!activeTask(t)))&&`${t.data.title} ${subjectNames.get(t.data.subjectId)||''}`.toLocaleLowerCase('ru').includes(query));
 const now=Date.now();
 return <section className="assignments" aria-label="Все задания">
  <div className="assignments-toolbar">
   <div className="assignment-filters" role="group" aria-label="Статус заданий">
    {([['all','Все'],['open','Открытые'],['accepted','Принятые']] as const).map(([value,label])=><button key={value} aria-pressed={filter===value} onClick={()=>setFilter(value)}>{label}</button>)}
   </div>
   <button className="outline assignment-add" onClick={onAdd}><Plus size={16}/> Добавить задание</button>
  </div>
  <div className="assignment-summary"><span><ArrowUpDown size={14}/> По дедлайну · сначала ближайшие</span><span role="status">Показано: {visible.length}</span></div>
  {visible.length?<ol className="assignment-list">{visible.map(t=>{
   const done=!activeTask(t);
   const overdue=!done&&!!t.data.deadline&&new Date(t.data.deadline).getTime()<now;
   return <li key={t.id}><button className={'assignment-row'+(done?' is-accepted':'')+(overdue?' is-overdue':'')} data-task-id={t.id} onClick={()=>onEdit(t)}>
    <span className="assignment-marker" aria-hidden="true">{done?<Check size={17}/>:<FileText size={17}/>}</span>
    <span className="assignment-copy"><strong>{t.data.title}</strong><span className="assignment-subject">{subjectNames.get(t.data.subjectId)||'Предмет не найден'}</span><span className="assignment-status">{labels[t.data.status]}</span></span>
    <span className="assignment-deadline">{t.data.deadline?<><time dateTime={t.data.deadline}>{dateLabel(t.data.deadline,timezone)}<span>{new Intl.DateTimeFormat('ru',{hour:'2-digit',minute:'2-digit',timeZone:timezone}).format(new Date(t.data.deadline))}</span></time>{overdue&&<span className="assignment-overdue"><Clock size={12}/> Просрочено</span>}</>:<span className="muted">Без срока</span>}</span>
    <ChevronRight className="assignment-chevron" size={16} aria-hidden="true"/>
   </button></li>;
  })}</ol>:<div className="empty-state"><FileText size={34} strokeWidth={1}/><h3>{tasks.length?'Заданий не найдено':'Начнём с одного задания'}</h3><p>{tasks.length?'Попробуйте другой запрос или выберите «Все».':'Добавьте домашку — здесь появятся задания по всем предметам в порядке дедлайнов.'}</p>{!tasks.length&&<button className="outline" onClick={onAdd}><Plus size={16}/> Добавить задание</button>}</div>}
 </section>;
}
