import {useId,useLayoutEffect,useRef,useState} from 'react';
import {parseTimeInput,replaceTimeSegment,typeTimeDigit,type TimeSegment} from './timeInput';

export default function TimeField({label,value,onChange}:{label:string;value:string;onChange:(value:string)=>void}) {
  const id=useId();
  const input=useRef<HTMLInputElement>(null);
  const pending=useRef('');
  const lastDigit=useRef(0);
  const clicked=useRef(false);
  const [segment,setSegment]=useState<TimeSegment>('hours');
  const [error,setError]=useState('');
  const displayed=value.slice(0,5);
  function select(part:TimeSegment) {
    input.current?.setSelectionRange(part==='hours'?0:3,part==='hours'?2:5);
  }
  function activate(part:TimeSegment) {
    input.current?.focus();
    pending.current='';setSegment(part);select(part);
  }
  function commit(next:string) {
    setError('');input.current?.setCustomValidity('');onChange(next);
  }
  useLayoutEffect(()=>{if(document.activeElement===input.current)select(segment)},[displayed,segment]);
  return <div className="time-field">
    <label htmlFor={id}>{label}</label>
    <input ref={input} id={id} type="text" inputMode="numeric" autoComplete="off" spellCheck={false}
      required pattern="([01][0-9]|2[0-3]):[0-5][0-9]" value={displayed}
      aria-describedby={id+'-hint'} aria-invalid={!!error}
      onFocus={()=>{pending.current='';clicked.current=false;setSegment('hours');select('hours')}}
      onBlur={()=>{pending.current='';clicked.current=false}}
      onClick={()=>{const next=clicked.current?(segment==='hours'?'minutes':'hours'):'hours';activate(next);clicked.current=true}}
      onChange={e=>{
        // Also accepts text replacement from assistive input methods.
        const next=parseTimeInput(e.target.value);
        if(next)commit(next);
        else {e.target.value=displayed;select(segment)}
      }}
      onPaste={e=>{
        e.preventDefault();const next=parseTimeInput(e.clipboardData.getData('text'));
        if(next){commit(next);activate('minutes')}
        else {const message='Введите время от 00:00 до 23:59, например 09:30.';setError(message);input.current?.setCustomValidity(message)}
      }}
      onKeyDown={e=>{
        if(e.metaKey||e.ctrlKey||e.altKey)return;
        if(/^\d$/.test(e.key)){
          e.preventDefault();
          const replaceAll=input.current?.selectionStart===0&&input.current?.selectionEnd===5;
          if(replaceAll||Date.now()-lastDigit.current>1500)pending.current='';
          const next=typeTimeDigit({value:displayed,segment:replaceAll?'hours':segment,pending:pending.current},e.key);
          pending.current=next.pending;lastDigit.current=Date.now();clicked.current=true;
          commit(next.value);setSegment(next.segment);select(next.segment);
        }else if(e.key==='ArrowUp'||e.key==='ArrowDown'){
          e.preventDefault();pending.current='';
          const max=segment==='hours'?24:60;
          const current=Number(displayed.slice(segment==='hours'?0:3,segment==='hours'?2:5));
          commit(replaceTimeSegment(displayed,segment,(current+(e.key==='ArrowUp'?1:-1)+max)%max));
        }else if(e.key==='ArrowLeft'||e.key==='Home'){
          e.preventDefault();activate('hours');
        }else if(e.key==='ArrowRight'||e.key==='End'||e.key===':'){
          e.preventDefault();activate('minutes');
        }else if(e.key==='Tab'&&((!e.shiftKey&&segment==='hours')||(e.shiftKey&&segment==='minutes'))){
          e.preventDefault();activate(e.shiftKey?'hours':'minutes');
        }else if(e.key==='Backspace'||e.key==='Delete'){
          e.preventDefault();pending.current='';commit(replaceTimeSegment(displayed,segment,0));select(segment);
        }else if(e.key.length===1){e.preventDefault()}
      }}/>
    <div className="time-segments" role="group" aria-label={label+': изменяемая часть времени'}>
      <button type="button" aria-pressed={segment==='hours'} onClick={()=>activate('hours')}>Часы</button>
      <button type="button" aria-pressed={segment==='minutes'} onClick={()=>activate('minutes')}>Минуты</button>
    </div>
    <span id={id+'-hint'} className={error?'time-error':'sr-only'}>{error||'Повторное нажатие переключает часы и минуты. Стрелки вверх и вниз изменяют значение.'}</span>
  </div>;
}
