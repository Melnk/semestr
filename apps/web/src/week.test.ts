import {it,expect} from 'vitest';
import {daySegments,layoutEvents} from './Week';
it('показывает обе части занятия, пересекающего полночь в поясе пользователя',()=>{const o={lessonId:'1',subjectId:'2',title:'Практика',startsAt:'2026-10-07T18:30:00Z',endsAt:'2026-10-07T20:00:00Z',onlineUrl:'',room:'',type:'practice',originalDate:'2026-10-07',changed:false,conflict:false};expect(daySegments('2026-10-07',[o],[],'Asia/Yekaterinburg')[0]).toMatchObject({start:1410,end:1440});expect(daySegments('2026-10-08',[o],[],'Asia/Yekaterinburg')[0]).toMatchObject({start:0,end:60});expect(daySegments('2026-10-09',[o],[],'Asia/Yekaterinburg')).toHaveLength(0)});

it('разводит цепочку пересекающихся событий по стабильным колонкам',()=>{const events=[{key:'a',start:0,end:100},{key:'b',start:10,end:200},{key:'c',start:110,end:300}].map(e=>({...e,title:'Пара',time:'',detail:'',conflict:true}));expect(layoutEvents(events).map(e=>[e.lane,e.lanes])).toEqual([[0,2],[1,2],[0,2]])});
