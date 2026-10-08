import {useState} from 'react';
import {CheckCircle2,FileJson,FolderOpen,X} from 'lucide-react';
import {nativeAction} from '@semestr/api-client';

export type TransferFile={token:string;name:string;folder:string;size:number};
export type ImportedFile<T>={bundle:T;file:TransferFile};
export type ExportedFile={file:TransferFile;settings:boolean};
type ExportResult={saved:false}|{saved:true;file:TransferFile};

export async function saveNativeFile(settings=false){
 const result=await nativeAction<ExportResult>(settings?'exportSettings':'export');
 if(result.saved)window.dispatchEvent(new CustomEvent<ExportedFile>('semestr:file-exported',{detail:{file:result.file,settings}}));
 return result;
}

export function fileSize(size:number){
 if(size<1024)return `${size} Б`;
 return `${new Intl.NumberFormat('ru',{maximumFractionDigits:1}).format(size/(size<1048576?1024:1048576))} ${size<1048576?'КБ':'МБ'}`;
}

export function FileSummary({file}:{file:Pick<TransferFile,'name'|'size'>&{folder?:string}}){
 return <div className="transfer-file"><FileJson size={24} strokeWidth={1.5}/><div><strong title={file.name}>{file.name}</strong><span>{fileSize(file.size)}{file.folder&&<> · <span title={file.folder}>{file.folder}</span></>}</span></div></div>;
}

export function SavedFileNotice({exported,onClose}:{exported:ExportedFile;onClose:()=>void}){
 const[busy,setBusy]=useState(false);const[error,setError]=useState('');
 async function reveal(){
  setBusy(true);setError('');
  try{await nativeAction('revealTransferFile',{token:exported.file.token})}catch(e){setError((e as Error).message)}finally{setBusy(false)}
 }
 return <div className="saved-file-notice" role="status" aria-label="Сохранённый файл">
  <div className="saved-file-heading"><span><CheckCircle2 size={16}/>{exported.settings?'Файл настроек сохранён':'Файл учебных данных сохранён'}</span><button className="icon-button" aria-label="Скрыть сохранённый файл" onClick={onClose}><X size={17}/></button></div>
  <FileSummary file={exported.file}/>
  <button className="outline reveal-file" disabled={busy} onClick={()=>void reveal()}><FolderOpen size={17}/>Показать в Finder</button>
  {error&&<p className="error" role="alert">{error}</p>}
 </div>;
}
