import type {Data,Subject,StudyRecord,Debt,Task} from '@semestr/api-client';
export const labels:Record<string,string>={unknown:'Не уточнена',exam:'Экзамен',credit:'Зачёт',graded_credit:'Зачёт с оценкой',studying:'Изучается',ready:'Готов к сдаче',closed:'Закрыт',todo:'Нужно сделать',in_progress:'В работе',submitted:'Отправлено',accepted:'Принято',revision:'Нужны исправления',clarify:'Уточнить требования',working:'Выполняю',review:'Ожидаю проверки',difference:'Академическая разница',overdue:'Задолженность',retake:'Пересдача',lecture:'Лекция',practice:'Практика',lab:'Лабораторная',all:'Каждую неделю',even:'Чётные недели',odd:'Нечётные недели'};
export const dateLabel=(date?:string|null,timezone?:string)=>date?new Intl.DateTimeFormat('ru',{...(date.length>10&&timezone?{timeZone:timezone}:{}),day:'numeric',month:'long',year:'numeric'}).format(new Date(date.length===10?date+'T12:00:00':date)).replace(' г.',''):'Без срока';
export function localDate(d:Date){return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`}
export function contextText(subject:Subject,records:StudyRecord[]){return [`Предмет: ${subject.title}`,`Преподаватель: ${subject.teacher||'Не уточнён'}`,`Аттестация: ${labels[subject.assessment]}`,`Условия сдачи: ${subject.requirements||'Не уточнены'}`,`Допуск: ${subject.admission||'Не уточнён'}`,`Статус: ${labels[subject.status]}`,...records.map(({data:d})=>d.kind==='debt'?`Долг: ${labels[d.reason]}; срок: ${dateLabel(d.deadline)}; статус: ${labels[d.status]}; требования: ${d.requirements}; следующий шаг: ${d.nextStep}; подтверждение: ${d.confirmation}; заметки: ${d.notes}`:d.kind==='task'?`Задание: ${d.title}; ${labels[d.status]}; срок: ${d.deadline||'не задан'}; ${d.description}; результат: ${d.resultUrl}; заметки: ${d.notes}; ссылки: ${d.links.map(l=>l.url).join(', ')}`:d.kind==='note'?`Заметка: ${d.text}`:''),...subject.links.map(l=>`${l.title}: ${l.url}`)].filter(Boolean).join('\n')}
export function emptyData(kind:Data['kind'],subjectId:string,timezone:string,weekOne:string):Data {
 const today=localDate(new Date());
 switch(kind){
 case 'subject':return{kind,title:'',semester:'',description:'',teacher:'',contact:'',assessment:'unknown',requirements:'',admission:'',onlineUrl:'',links:[],status:'studying'};
 case 'task':return{kind,subjectId,title:'',description:'',deadline:null,status:'todo',debtId:null,lessonId:null,links:[],resultUrl:'',notes:''};
 case 'debt':return{kind,subjectId,reason:'difference',deadline:null,requirements:'',nextStep:'',teacher:'',status:'clarify',closedAt:null,confirmation:'',notes:''};
 case 'lesson':return{kind,subjectId,weekday:1,startTime:'09:00',endTime:'10:30',type:'practice',validFrom:today,validUntil:localDate(new Date(new Date().setMonth(new Date().getMonth()+4))),timezone,parity:'all',weekOne,onlineUrl:'',room:''};
 case 'note':return{kind,subjectId,text:''};}
}
export function typed<T extends Data>(records:StudyRecord[],kind:T['kind']){return records.filter(r=>r.data.kind===kind) as StudyRecord<T>[]}
export const activeDebt=(r:StudyRecord<Debt>)=>r.data.status!=='closed';
export const activeTask=(r:StudyRecord<Task>)=>r.data.status!=='accepted';
