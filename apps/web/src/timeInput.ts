export type TimeSegment = 'hours' | 'minutes';
export type TimeEdit = {value:string; segment:TimeSegment; pending:string};

export function parseTimeInput(text:string):string|null {
  const match = /^(\d{1,2}):(\d{2})$/.exec(text.trim());
  if (!match || Number(match[1]) > 23 || Number(match[2]) > 59) return null;
  return `${match[1].padStart(2,'0')}:${match[2]}`;
}

export function replaceTimeSegment(value:string, segment:TimeSegment, number:number):string {
  const parts = value.slice(0,5).split(':');
  parts[segment === 'hours' ? 0 : 1] = String(number).padStart(2,'0');
  return parts.join(':');
}

export function typeTimeDigit(edit:TimeEdit, digit:string):TimeEdit {
  const max = edit.segment === 'hours' ? 23 : 59;
  const pair = edit.pending + digit;
  const number = Number(pair) <= max ? Number(pair) : Number(digit);
  const complete = pair.length === 2 || Number(digit) > Math.floor(max / 10);
  return {
    value:replaceTimeSegment(edit.value,edit.segment,number),
    segment:complete ? 'minutes' : edit.segment,
    pending:complete ? '' : digit,
  };
}
