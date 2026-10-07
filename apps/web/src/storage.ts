export function readPreference(key:string,fallback:string){try{return localStorage.getItem(key)||fallback}catch{return fallback}}
export function writePreference(key:string,value:string){try{localStorage.setItem(key,value)}catch{/* Preferences remain in memory if device storage is unavailable. */}}
export function clearDrafts(accountId:string){try{Object.keys(localStorage).filter(k=>k.startsWith(`semestr:draft:${accountId}:`)).forEach(k=>localStorage.removeItem(k))}catch{/* Revoking the server session must not depend on browser storage. */}}
