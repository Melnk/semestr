import type {StudyRecord,Subject} from '@semestr/api-client';

type Props={
 subjects:StudyRecord<Subject>[];
 mode:'new'|'existing';
 title:string;
 subjectId:string;
 onMode:(mode:'new'|'existing')=>void;
 onTitle:(title:string)=>void;
 onSelect:(id:string)=>void;
};

export default function DebtSubjectField({subjects,mode,title,subjectId,onMode,onTitle,onSelect}:Props){
 const sameTitle=subjects.filter(s=>s.data.title.trim().toLocaleLowerCase('ru')===title.trim().toLocaleLowerCase('ru'));
 return <fieldset className="debt-subject-field">
  <legend>Предмет</legend>
  {subjects.length>0&&<div className="subject-mode" role="group" aria-label="Предмет для долга">
   <button type="button" aria-pressed={mode==='new'} onClick={()=>onMode('new')}>Новый предмет</button>
   <button type="button" aria-pressed={mode==='existing'} onClick={()=>onMode('existing')}>Выбрать из моих</button>
  </div>}
  {mode==='new'?<>
   <label>Название предмета<input id="debt-subject-title" autoFocus required maxLength={300} placeholder="Например, основы финансовой грамотности" value={title} onChange={e=>onTitle(e.target.value)}/></label>
   <p className="muted small">Предмет добавится вместе с долгом. Сейчас достаточно названия — остальные сведения можно заполнить позже.</p>
   {title.trim()&&sameTitle.length>0&&<div className="subject-matches">
    <p className="muted small">Такой предмет уже есть в списке. Можно использовать его:</p>
    {sameTitle.map(s=><button type="button" className="text-button" key={s.id} onClick={()=>{onSelect(s.id);onMode('existing')}}>{s.data.title}{s.data.semester?' · '+s.data.semester:''}{s.data.teacher?' · '+s.data.teacher:''}</button>)}
   </div>}
  </>:<label>Ваш предмет<select id="debt-existing-subject" required value={subjectId} onChange={e=>onSelect(e.target.value)}>
   <option value="">Выберите предмет</option>
   {subjects.map(s=><option key={s.id} value={s.id}>{s.data.title}{s.data.semester?' · '+s.data.semester:''}</option>)}
  </select></label>}
 </fieldset>
}
