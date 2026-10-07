import {Pencil,Plus} from 'lucide-react';

export default function RequirementsCard({text,onEdit}:{text:string;onEdit:()=>void}) {
  const empty=!text.trim();
  return <button className={'requirements-card'+(empty?' is-empty':'')} onClick={onEdit}>
    <span className="requirements-text">{empty?'Что нужно сделать для сдачи?':text}</span>
    {empty&&<span className="requirements-hint">Запишите работы, требования и формат сдачи.</span>}
    <span className="requirements-edit">{empty?<Plus size={13}/>:<Pencil size={12}/>} {empty?'Добавить условия':'Изменить условия'}</span>
  </button>;
}
