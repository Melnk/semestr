import {describe,it,expect} from 'vitest';
import {contextText,emptyData,sortSubjects,sortTasks} from './utils';
import type {Subject,StudyRecord,Task} from '@semestr/api-client';
describe('контекст предмета',()=>{it('собирает требования, статусы, срок и подтверждение, не обращаясь к AI',()=>{const subject={...emptyData('subject','','',''),title:'Алгебра',requirements:'Две работы'} as Subject;const records:StudyRecord[]=[{id:'1',version:0,data:{kind:'debt',subjectId:'s',reason:'retake',deadline:'2026-12-15',requirements:'Защита',nextStep:'Записаться',teacher:'',status:'closed',closedAt:'2026-10-01',confirmation:'Оценка внесена',notes:''}},{id:'2',version:0,data:{...emptyData('task','s','',''),kind:'task',subjectId:'s',title:'Первая работа',status:'submitted',description:'',deadline:null,debtId:null,lessonId:null,links:[],resultUrl:'',notes:''}}];const context=contextText(subject,records);expect(context).toContain('Две работы');expect(context).toContain('Оценка внесена');expect(context).toContain('Отправлено');expect(context).toContain('15 декабря 2026')})});

it('ставит экзамены первыми, сортирует названия внутри групп и не меняет исходный список',()=>{
 const records=[['Язык','credit'],['Базы данных','exam'],['Алгебра','exam'],['Анализ','graded_credit'],['История','unknown']].map(([title,assessment],i)=>({id:String(i),version:0,data:{...emptyData('subject','','',''),kind:'subject',title,assessment}})) as StudyRecord<Subject>[];
 expect(sortSubjects(records).map(r=>r.data.title)).toEqual(['Алгебра','Базы данных','Анализ','История','Язык']);
 expect(records[0].data.title).toBe('Язык');
});

it('сортирует все задания по моменту дедлайна, без срока — в конце, не меняя исходные записи',()=>{
 const task=(id:string,title:string,deadline:string|null,status:Task['status']='todo'):StudyRecord<Task>=>({id,version:0,data:{...emptyData('task','s','','') as Task,title,deadline,status}});
 const tasks=[task('none-b','Язык',null),task('later','Ближайший по строке','2026-10-13T09:00:00Z'),task('early','Просроченное','2026-10-12T09:00:00Z'),task('same-z','Язык','2026-10-13T12:00:00+05:00'),task('none-a','Алгебра',null),task('same-a','Алгебра','2026-10-13T07:00:00Z','accepted')];
 expect(sortTasks(tasks).map(t=>t.id)).toEqual(['early','same-a','same-z','later','none-a','none-b']);
 expect(tasks.map(t=>t.id)).toEqual(['none-b','later','early','same-z','none-a','same-a']);
 expect(sortTasks([])).toEqual([]);
});
