package dev.semestr.transfer

import dev.semestr.study.*
import dev.semestr.accounts.*
import dev.semestr.schedule.Recurrence
import dev.semestr.common.*
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.util.UUID
import java.time.ZoneId

data class ExportBundle(val formatVersion:Int=1,val profile:Profile,val records:List<StudyRecord>,val exceptions:List<ExceptionData> = emptyList())
data class ImportRequest(val bundle:ExportBundle,val mode:String="add",val expectedRevision:Long,val confirmed:Boolean=false)
data class ImportPreview(val subjects:Int,val tasks:Int,val debts:Int,val lessons:Int,val notes:Int,val exceptions:Int)
@Service
class TransferService(val repo:StudyRepository,val study:StudyService,val auth:AuthService) {
 @Transactional(readOnly=true,isolation=org.springframework.transaction.annotation.Isolation.REPEATABLE_READ)
 fun export(user:UUID)=ExportBundle(profile=auth.account(user).profile,records=repo.all(user),exceptions=repo.exceptions(user))
 fun validate(user:UUID,bundle:ExportBundle):ImportPreview {
  requireValid(bundle.formatVersion==1,"Версия формата не поддерживается");requireValid(bundle.records.size<=10000 && bundle.exceptions.size<=10000,"Не более 10 000 записей и исключений за импорт")
  ZoneId.of(bundle.profile.timezone);requireValid(bundle.profile.weekOne.dayOfWeek==java.time.DayOfWeek.MONDAY,"Неделя № 1 должна начинаться в понедельник")
  requireValid(listOf(bundle.profile.name,bundle.profile.university,bundle.profile.direction,bundle.profile.group,bundle.profile.semester).all{it.length<=300},"Слишком длинное поле профиля")
  val map=bundle.records.associateBy{it.id};requireValid(map.size==bundle.records.size,"В файле повторяются идентификаторы")
  bundle.records.forEach{Rules.validate(it.data);study.validateRelations(user,it.data,map)}
  requireValid(bundle.exceptions.map{it.lessonId to it.originalDate}.distinct().size==bundle.exceptions.size,"Повторяющиеся исключения")
  bundle.exceptions.forEach{e->val l=map[e.lessonId]?.data as? Lesson;requireValid(l!=null && Recurrence.matches(l,e.originalDate),"Исключение не соответствует занятию");requireValid((e.startsAt==null && e.endsAt==null) || (e.startsAt!=null && e.endsAt!=null && e.endsAt>e.startsAt && java.time.Duration.between(e.startsAt,e.endsAt).toHours()<=24),"Некорректный перенос")}
  fun count(kind:String)=bundle.records.count{it.data.kind()==kind}
  return ImportPreview(count("subject"),count("task"),count("debt"),count("lesson"),count("note"),bundle.exceptions.size)
 }
 @Transactional
 fun apply(user:UUID,body:ImportRequest):ImportPreview {
  val revision=repo.lock(user);if(revision!=body.expectedRevision)throw ApiException(409,"conflict","Данные изменились после предпросмотра. Проверьте импорт снова.")
  requireValid(body.mode in setOf("add","replace"),"Неизвестный режим импорта");requireValid(body.mode!="replace" || body.confirmed,"Подтвердите замену всех данных")
  val preview=validate(user,body.bundle)
  if(body.mode=="replace") {repo.db.update("DELETE FROM lesson_exceptions WHERE user_id=?",user);repo.db.update("DELETE FROM study_records WHERE user_id=?",user);repo.db.update("UPDATE accounts SET profile=?::jsonb,version=version+1 WHERE id=?",repo.json.writeValueAsString(body.bundle.profile),user)}
  val ids=body.bundle.records.associate{it.id to UUID.randomUUID()}
  body.bundle.records.forEach{r->val d=when(val d=r.data){is Subject->d;is Debt->d.copy(subjectId=ids.getValue(d.subjectId));is Task->d.copy(subjectId=ids.getValue(d.subjectId),debtId=d.debtId?.let{ids.getValue(it)},lessonId=d.lessonId?.let{ids.getValue(it)});is Lesson->d.copy(subjectId=ids.getValue(d.subjectId));is Note->d.copy(subjectId=ids.getValue(d.subjectId))};repo.save(user,ids.getValue(r.id),d,null)}
  body.bundle.exceptions.forEach{e->repo.db.update("INSERT INTO lesson_exceptions(id,user_id,lesson_id,original_date,starts_at,ends_at) VALUES (?,?,?,?,?,?)",UUID.randomUUID(),user,ids.getValue(e.lessonId),e.originalDate,e.startsAt?.let{java.sql.Timestamp.from(it)},e.endsAt?.let{java.sql.Timestamp.from(it)})}
  repo.bump(user);return preview
 }
}
