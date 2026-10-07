package dev.semestr.schedule

import dev.semestr.study.*
import dev.semestr.common.*
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.*
import java.time.temporal.ChronoUnit
import java.util.UUID

object Recurrence {
 fun matches(lesson:Lesson,date:LocalDate):Boolean {
  if(date<lesson.validFrom || date>lesson.validUntil || date.dayOfWeek.value!=lesson.weekday)return false
  val week=Math.floorDiv(ChronoUnit.DAYS.between(lesson.weekOne,date),7)+1
  return lesson.parity=="all" || (lesson.parity=="even" && Math.floorMod(week,2L)==0L) || (lesson.parity=="odd" && Math.floorMod(week,2L)==1L)
 }
 fun times(lesson:Lesson,date:LocalDate):Pair<Instant,Instant> {
  val zone=ZoneId.of(lesson.timezone)
  val endDate=if(lesson.endTime<=lesson.startTime)date.plusDays(1)else date
  return date.atTime(lesson.startTime).atZone(zone).toInstant() to endDate.atTime(lesson.endTime).atZone(zone).toInstant()
 }
}
@Service
class ScheduleService(val repo:StudyRepository) {
 @Transactional
 fun restore(user:UUID,id:UUID,version:Long) {
  repo.lock(user)
  if(repo.exceptions(user).none{it.id==id})throw ApiException(404,"not_found","Исключение не найдено")
  if(repo.db.update("DELETE FROM lesson_exceptions WHERE user_id=? AND id=? AND version=?",user,id,version)!=1)throw ApiException(409,"conflict","Исключение изменилось на другом устройстве")
  repo.bump(user)
 }
 fun occurrences(user:UUID,from:Instant,until:Instant):List<Occurrence> {
  requireValid(until>from && Duration.between(from,until).toDays()<=62,"Диапазон: от 1 минуты до 62 дней")
  val records=repo.all(user);val subjects=records.filter{it.data is Subject}.associateBy{it.id};val changes=repo.exceptions(user)
  val result=mutableListOf<Occurrence>()
  for(record in records.filter{it.data is Lesson}) {
   val l=record.data as Lesson;val subject=subjects[l.subjectId]?.data as? Subject ?: continue
   val overrides=changes.filter{it.lessonId==record.id}.associateBy{it.originalDate}
   val zone=ZoneId.of(l.timezone)
   fun add(date:LocalDate,start:Instant,end:Instant,changed:Boolean) { if(start<until && end>from)result.add(Occurrence(record.id,l.subjectId,subject.title,start,end,l.onlineUrl.ifBlank{subject.onlineUrl},l.room,l.type,date,changed)) }
   var date=from.atZone(zone).toLocalDate().minusDays(1);val last=until.atZone(zone).toLocalDate()
   while(date<=last) { if(Recurrence.matches(l,date) && date !in overrides) {val(s,e)=Recurrence.times(l,date);add(date,s,e,false)};date=date.plusDays(1) }
   overrides.values.forEach {if(it.startsAt!=null && it.endsAt!=null)add(it.originalDate,it.startsAt,it.endsAt,true)}
  }
  return result.sortedBy{it.startsAt}.map{a->a.copy(conflict=result.any{b->a!==b && a.startsAt<b.endsAt && a.endsAt>b.startsAt})}
 }
 @Transactional
 fun exception(user:UUID,lessonId:UUID,body:ExceptionWrite):ExceptionData {
  repo.lock(user);val l=repo.get(user,lessonId).data as? Lesson ?: throw ApiException(422,"validation","Не занятие")
  requireValid(Recurrence.matches(l,body.originalDate),"В этот день занятия в серии нет")
  requireValid((body.startsAt==null && body.endsAt==null) || (body.startsAt!=null && body.endsAt!=null && body.endsAt>body.startsAt && Duration.between(body.startsAt,body.endsAt).toHours()<=24),"Укажите корректные начало и конец переноса")
  val existing=repo.exceptions(user).find{it.lessonId==lessonId && it.originalDate==body.originalDate}
  if(existing==null) {requireValid(body.version==null,"Исключение не найдено");repo.db.update("INSERT INTO lesson_exceptions(id,user_id,lesson_id,original_date,starts_at,ends_at) VALUES (?,?,?,?,?,?)",UUID.randomUUID(),user,lessonId,body.originalDate,body.startsAt?.let{java.sql.Timestamp.from(it)},body.endsAt?.let{java.sql.Timestamp.from(it)})}
  else if(body.version!=existing.version)throw ApiException(409,"conflict","Исключение уже изменено")
  else repo.db.update("UPDATE lesson_exceptions SET starts_at=?,ends_at=?,version=version+1 WHERE user_id=? AND id=?",body.startsAt?.let{java.sql.Timestamp.from(it)},body.endsAt?.let{java.sql.Timestamp.from(it)},user,existing.id)
  repo.bump(user);return repo.exceptions(user).first{it.lessonId==lessonId && it.originalDate==body.originalDate}
 }
}
