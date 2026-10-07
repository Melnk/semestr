import {BookOpen,FlaskConical,PenLine} from 'lucide-react';
import {labels} from './utils';

export default function LessonBadge({type,compact=false}:{type:string;compact?:boolean}) {
  const Icon=type==='practice'?PenLine:type==='lab'?FlaskConical:BookOpen;
  const short=type==='practice'?'Пр.':type==='lab'?'Лаб.':'Лек.';
  return <span className={'lesson-badge lesson-'+type} title={labels[type]}><Icon size={11} aria-hidden="true"/>{compact?short:labels[type]||type}</span>;
}
