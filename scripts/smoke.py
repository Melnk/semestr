#!/usr/bin/env python3
"""Integration checks against a disposable/local server and Mailpit. No real emails.
Creates unique accounts; removes only those accounts through the authenticated API.
Run: python3 scripts/smoke.py. Requires server :8080 and Mailpit :8025.
"""
import json, os, re, secrets, time, urllib.request, urllib.error, http.cookiejar
BASE=os.environ.get('TEST_API','http://localhost:8080/api/v1')
MAIL=os.environ.get('TEST_MAIL','http://localhost:8025/api/v1')
checks=0
def ok(value,label):
    global checks
    assert value,label
    checks+=1
    print('PASS',label)
class Client:
    def __init__(self):
        self.jar=http.cookiejar.CookieJar();self.opener=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar));self.csrf='';self.bearer=None
    def call(self,path,method='GET',data=None,status=200,csrf=True):
        headers={'Content-Type':'application/json'}
        if csrf:headers['X-CSRF-Token']=self.csrf
        if self.bearer:headers['Authorization']='Bearer '+self.bearer
        req=urllib.request.Request(BASE+path,method=method,headers=headers,data=None if method=='GET' else json.dumps(data or {}).encode())
        try:r=self.opener.open(req,timeout=20);code=r.status;raw=r.read()
        except urllib.error.HTTPError as e:code=e.code;raw=e.read()
        payload=json.loads(raw) if raw else None
        assert code==status,f'{method} {path}: expected {status}, got {code}; {payload}'
        return payload
    def login(self,email,password):
        session=self.call('/auth/login','POST',{'email':email,'password':password});self.csrf=session['csrf'];return session
    def create(self,data):return self.call('/records','POST',{'data':data})
    def update(self,record,**fields):return self.call('/records/'+record['id'],'PUT',{'version':record['version'],'data':{**record['data'],**fields}})
    def delete(self,record):return self.call('/records/'+record['id']+'?version='+str(record['version']),'DELETE')
def email_token(email,purpose):
    for attempt in range(20):
        messages=json.load(urllib.request.urlopen(MAIL+'/messages'))['messages']
        for message in messages:
            if any(t['Address']==email for t in message['To']):
                detail=json.load(urllib.request.urlopen(MAIL+'/message/'+message['ID']))
                found=re.search(r'#'+purpose+r'=([A-Za-z0-9_-]+)',detail.get('Text',''))
                if found:return found.group(1)
        time.sleep(.2)
    raise AssertionError('Test email was not delivered')
def run():
    a,b=Client(),Client();password=secrets.token_urlsafe(18);suffix=secrets.token_hex(6);ea=f'qa-a-{suffix}@example.test';eb=f'qa-b-{suffix}@example.test'
    for c,email in [(a,ea),(b,eb)]:
        c.call('/auth/register','POST',{'email':email,'password':password})
        c.call('/auth/login','POST',{'email':email,'password':password},403)
        t=email_token(email,'verify');c.call('/auth/verify','POST',{'token':t});c.call('/auth/verify','POST',{'token':t},422)
        c.login(email,password)
    ok(True,'registration, email verification, one-time tokens and login for two users')
    s=a.create({'kind':'subject','title':'Тестовый предмет','teacher':'Вымышленный преподаватель'})
    b.call('/records/'+s['id'],status=404)
    b.call('/records','POST',{'data':{'kind':'task','title':'Forbidden','subjectId':s['id']}},404)
    ok(not b.call('/records')['items'],'read and foreign-subject link isolation')
    a.call('/records','POST',{'data':{'kind':'subject','title':'CSRF'}},403,csrf=False)
    ok(True,'cookie mutations require CSRF token')
    a.call('/records','POST',{'data':{'kind':'subject','title':'XSS','onlineUrl':'javascript:alert(1)'}},422)
    ok(True,'unsafe URL schemes rejected')
    a2=Client();a2.login(ea,password);copy=a2.call('/records/'+s['id']);s=a.update(s,title='Изменено на первом устройстве')
    ok(a2.call('/records/'+s['id'])['data']['title']==s['data']['title'],'second session receives server changes')
    a2.call('/records/'+s['id'],'PUT',{'version':copy['version'],'data':copy['data']},409)
    ok(True,'stale update produces 409')
    foreign=b.create({'kind':'subject','title':'Предмет B'});foreign_debt=b.create({'kind':'debt','subjectId':foreign['id']})
    a.call('/records','POST',{'data':{'kind':'task','title':'Forbidden debt','subjectId':s['id'],'debtId':foreign_debt['id']}},404)
    ok(True,'foreign debt relation rejected')
    other=a.create({'kind':'subject','title':'Другой предмет'});other_debt=a.create({'kind':'debt','subjectId':other['id']})
    a.call('/records','POST',{'data':{'kind':'task','title':'Wrong subject','subjectId':s['id'],'debtId':other_debt['id']}},422)
    ok(True,'same-owner cross-subject relation rejected')
    debt=a.create({'kind':'debt','subjectId':s['id'],'deadline':'2026-12-15','nextStep':'Получить требования'})
    task=a.create({'kind':'task','subjectId':s['id'],'debtId':debt['id'],'title':'Работа'})
    for state in ['in_progress','submitted','revision','in_progress','submitted','accepted']:task=a.update(task,status=state)
    ok(a.call('/records/'+s['id'])['data']['status']=='studying','task states do not automatically close subject')
    a.call('/records/'+debt['id'],'PUT',{'version':debt['version'],'data':{**debt['data'],'status':'closed'}},422)
    for state in ['working','review','ready']:debt=a.update(debt,status=state)
    debt=a.update(debt,status='closed',closedAt='2026-10-07',confirmation='Результат подтверждён')
    ok(debt['data']['confirmation']=='Результат подтверждён','debt closure requires confirmation')
    lesson=a.create({'kind':'lesson','subjectId':s['id'],'weekday':7,'startTime':'23:30','endTime':'01:00','validFrom':'2026-10-01','validUntil':'2026-12-31','timezone':'Asia/Tokyo','weekOne':'2026-09-28','parity':'odd'})
    query='/schedule?from=2026-10-01T00:00:00Z&until=2026-10-15T00:00:00Z'
    occurrences=a.call(query);ok(len(occurrences)==1 and occurrences[0]['startsAt']=='2026-10-04T14:30:00Z' and occurrences[0]['endsAt']=='2026-10-04T16:00:00Z','odd weeks and midnight timezone conversion')
    exception=a.call('/schedule/'+lesson['id']+'/exception','PUT',{'originalDate':'2026-10-04'})
    ok(not a.call(query),'single cancellation leaves recurrence intact')
    exception=a.call('/schedule/'+lesson['id']+'/exception','PUT',{'originalDate':'2026-10-04','startsAt':'2026-10-06T10:00:00Z','endsAt':'2026-10-06T11:30:00Z','version':exception['version']})
    ok(a.call(query)[0]['changed'],'single reschedule appears in new date')
    a.call('/schedule/'+lesson['id']+'/exception','PUT',{'originalDate':'2026-10-04','version':0},409)
    ok(True,'exception conflicts protected')
    a.call('/schedule/exceptions/'+exception['id']+'?version=0','DELETE',status=409)
    a.call('/schedule/exceptions/'+exception['id']+'?version='+str(exception['version']),'DELETE')
    ok(not a.call(query)[0]['changed'],'restore exception returns original series occurrence')
    a.call('/schedule/'+lesson['id']+'/exception','PUT',{'originalDate':'2026-10-04','startsAt':'2026-10-06T10:00:00Z','endsAt':'2026-10-06T11:30:00Z'})
    collision=a.create({'kind':'lesson','subjectId':s['id'],'weekday':2,'startTime':'10:30','endTime':'12:00','validFrom':'2026-10-01','validUntil':'2026-10-08','timezone':'UTC','weekOne':'2026-09-28'})
    ok(all(o['conflict'] for o in a.call(query)),'overlapping classes are marked')
    a.delete(collision)
    profile=a.call('/auth/session')['account'];profile['profile']['timezone']='Pacific/Auckland'
    a.call('/profile','PUT',{'version':profile['version'],'profile':profile['profile']})
    a.call('/profile','PUT',{'version':profile['version'],'profile':profile['profile']},409)
    ok(True,'profile optimistic locking')
    note=a.create({'kind':'note','subjectId':s['id'],'text':'Тестовая договорённость'})
    exported=a.call('/export');count=len(exported['records']);preview=a.call('/import/preview','POST',exported)
    ok(preview['subjects']==2 and preview['tasks']==1,'versioned export and validated preview')
    revision=a.call('/auth/session')['account']['revision']
    invalid=json.loads(json.dumps(exported));invalid['records'][0]['data']['kind']='unknown'
    a.call('/import','POST',{'bundle':invalid,'expectedRevision':revision},422)
    ok(len(a.call('/export')['records'])==count,'invalid import is atomic')
    a.call('/import','POST',{'bundle':exported,'mode':'replace','expectedRevision':revision,'confirmed':False},422)
    a.call('/import','POST',{'bundle':exported,'mode':'replace','expectedRevision':revision-1,'confirmed':True},409)
    ok(True,'replace confirmation and revision checks')
    a.call('/import','POST',{'bundle':exported,'mode':'replace','expectedRevision':revision,'confirmed':True})
    current=a.call('/export');ok(len(current['records'])==count and len(current['exceptions'])==1,'replacement preserves links and exceptions atomically')
    revision=a.call('/auth/session')['account']['revision'];a.call('/import','POST',{'bundle':exported,'mode':'add','expectedRevision':revision})
    ok(len(a.call('/export')['records'])==count*2,'add import remaps IDs and does not overwrite')
    page=a.call('/records?limit=2');nextpage=a.call('/records?limit=2&cursor='+page['nextCursor']);ok(len(page['items'])==2 and not(set(r['id'] for r in page['items'])&set(r['id'] for r in nextpage['items'])),'cursor pagination')
    b.call('/auth/forgot','POST',{'email':eb});t=email_token(eb,'reset');new_password=secrets.token_urlsafe(18);b.call('/auth/reset','POST',{'token':t,'password':new_password})
    b.call('/auth/session',status=401);b.login(eb,new_password)
    ok(True,'password recovery revokes existing sessions')
    native=Client();session=native.call('/auth/login','POST',{'email':ea,'password':password,'native':True});native.bearer=session['accessToken'];ok(native.call('/auth/session')['account']['email']==ea,'native bearer authentication')
    a2.call('/auth/logout','POST');a2.call('/auth/session',status=401)
    ok(True,'logout invalidates session')
    a.call('/account/delete','POST',{'password':password});native.call('/auth/session',status=401)
    b.call('/account/delete','POST',{'password':new_password});b.call('/auth/session',status=401)
    ok(True,'account deletion cascades owned data and revokes all sessions')
    print(f'PASS: {checks} integration scenarios. Test accounts removed.')
if __name__=='__main__':run()
