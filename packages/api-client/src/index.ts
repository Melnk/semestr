import type {components} from './schema';
type S=components['schemas'];
export type Link=S['Link'];
export type Subject=Required<S['Subject']>;
export type Task=Required<S['Task']>;
export type Debt=Required<S['Debt']>;
export type Lesson=Required<S['Lesson']>;
export type Note=Required<S['Note']>;
export type Data=Subject|Task|Debt|Lesson|Note;
export type StudyRecord<T extends Data=Data>=Omit<S['StudyRecord'],'data'>&{data:T};
export type Profile=S['Profile'];
export type Account=S['AccountView'];
export type Session=S['SessionView'];
export type Occurrence=S['Occurrence'];
export type LessonException=Required<S['ExceptionData']>;
export type Bundle={formatVersion:number;profile:Profile;records:StudyRecord[];exceptions:LessonException[]};
export type Appearance={theme:'light'|'dark'};
export type NotificationPreferences={enabled:boolean;lessonsEnabled:boolean;lessonTypes:string[];lessonMinutes:number;deadlinesEnabled:boolean;deadlineMinutes:number[];debtTime:string;sound:boolean};
export type NotificationStatus={authorization:'notDetermined'|'denied'|'authorized'|'provisional';pendingCount:number;coveredUntil:string|null;truncated:boolean;error:string};
export type SettingsBundle={format:'semestr-settings';formatVersion:1;profile:Profile;appearance:Appearance;notifications?:NotificationPreferences};
export type SettingsPreview={bundle:SettingsBundle;expectedRevision:number};
export type SettingsApplied={account:Account;appearance:Appearance};
export class ApiError extends Error { constructor(public status:number,public code:string,message:string){super(message)} }
type NativeReply={ok:boolean;data?:unknown;status?:number;code?:string;message?:string};
declare global {interface Window {webkit?:{messageHandlers?:{semestr?:{postMessage:(message:unknown)=>Promise<NativeReply>}}}}}
export const isLocalApp=typeof window!=='undefined'&&!!window.webkit?.messageHandlers?.semestr;
export async function nativeAction<T=void>(action:string,parameters:Record<string,unknown>={}):Promise<T>{
 const bridge=window.webkit?.messageHandlers?.semestr;
 if(!bridge)throw new ApiError(0,'desktop','Откройте приложение Семестр на Mac.');
 const reply=await bridge.postMessage({action,...parameters});
 if(!reply.ok)throw new ApiError(reply.status??500,reply.code??'storage',reply.message??'Не удалось сохранить данные.');
 return reply.data as T;
}
export class ApiClient {
 private csrf='';
 constructor(private base='/api/v1'){}
 async request<T>(path:string,method='GET',body?:unknown):Promise<T> {
  if(isLocalApp)return nativeAction<T>('api',{path,method,body:body??{}});
  let response:Response;const abort=new AbortController();const timer=setTimeout(()=>abort.abort(),15000);
  try { response=await fetch(this.base+path,{method,signal:abort.signal,credentials:'include',headers:{'Content-Type':'application/json','X-CSRF-Token':this.csrf},...(method==='GET'?{}:{body:JSON.stringify(body??{})})}) }
  catch {throw new ApiError(0,'offline','Нет соединения с сервером. Изменения не сохранены.')}finally{clearTimeout(timer)}
  if(!response.ok){const error=await response.json().catch(()=>({code:'server',message:'Сервер недоступен. Попробуйте ещё раз.'}));throw new ApiError(response.status,error.code,error.message)}
  const text=await response.text();return (text?JSON.parse(text):undefined) as T;
 }
 async session(){const s=await this.request<Session>('/auth/session');this.csrf=s.csrf;return s}
 async login(email:string,password:string){const s=await this.request<Session>('/auth/login','POST',{email,password});this.csrf=s.csrf;return s}
 async records(){const result:StudyRecord[]=[];let cursor:string|null=null;do{const page: {items:StudyRecord[];nextCursor:string|null}=await this.request('/records?limit=200'+(cursor?'&cursor='+cursor:''));result.push(...page.items);cursor=page.nextCursor}while(cursor);return result}
 save(data:Data,existing?:StudyRecord){return this.request<StudyRecord>('/records'+(existing?'/'+existing.id:''),existing?'PUT':'POST',{data,...(existing?{version:existing.version}:{})})}
 createDebtWithSubject(data:Debt,subjectTitle:string){return this.request<{subject:StudyRecord<Subject>;debt:StudyRecord<Debt>}>('/debts/with-subject','POST',{data,subjectTitle})}
 schedule(from:Date,until:Date){return this.request<Occurrence[]>(`/schedule?from=${encodeURIComponent(from.toISOString())}&until=${encodeURIComponent(until.toISOString())}`)}
}
export const api=new ApiClient();
