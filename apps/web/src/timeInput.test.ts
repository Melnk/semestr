import {expect,it} from 'vitest';
import {parseTimeInput,typeTimeDigit,replaceTimeSegment,type TimeEdit} from './timeInput';

it('вводит время четырьмя цифрами и переводит выделение с часов на минуты',()=>{
  let edit:TimeEdit={value:'09:00',segment:'hours',pending:''};
  for(const digit of '1750')edit=typeTimeDigit(edit,digit);
  expect(edit).toEqual({value:'17:50',segment:'minutes',pending:''});
});
it('не допускает часы 24 и минуты 60; заменяет ошибочную пару последней цифрой',()=>{
  expect(typeTimeDigit({value:'02:00',segment:'hours',pending:'2'},'4').value).toBe('04:00');
  expect(typeTimeDigit({value:'23:05',segment:'minutes',pending:'5'},'9').value).toBe('23:59');
  expect(typeTimeDigit({value:'23:00',segment:'minutes',pending:''},'6')).toMatchObject({value:'23:06',pending:''});
  expect(replaceTimeSegment('23:59','minutes',0)).toBe('23:00');
});
it('проверяет вставленное время целиком, включая границы суток',()=>{
  expect(parseTimeInput(' 9:05 ')).toBe('09:05');
  expect(parseTimeInput('00:00')).toBe('00:00');
  expect(parseTimeInput('23:59')).toBe('23:59');
  for(const value of ['24:00','12:60','-1:00','99:99','12:30 extra','12:3',''])expect(parseTimeInput(value)).toBeNull();
});
