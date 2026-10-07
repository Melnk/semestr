package dev.semestr.study

import dev.semestr.common.requireValid
import java.net.URI
import java.time.*

object Rules {
 fun url(value:String) { requireValid(value.isBlank() || runCatching { val u=URI(value); u.scheme in setOf("http","https") && !u.host.isNullOrBlank() && u.userInfo==null }.getOrDefault(false),"Ссылка должна начинаться с https:// или http://") }
 fun validate(data:StudyData) {
  fun text(v:String,max:Int=20000) { requireValid(v.length<=max,"Слишком длинный текст") }
  fun title(v:String) { requireValid(v.isNotBlank() && v.length<=300,"Название: от 1 до 300 символов") }
  fun links(v:List<Link>) { requireValid(v.size<=30,"Не более 30 ссылок");v.forEach{title(it.title);url(it.url)} }
  when(data) {
   is Subject -> { title(data.title);text(data.semester,100);text(data.description);text(data.teacher,300);text(data.contact,500);text(data.requirements);text(data.admission);url(data.onlineUrl);links(data.links);requireValid(data.assessment in setOf("unknown","exam","credit","graded_credit"),"Неизвестная аттестация");requireValid(data.status in setOf("studying","ready","closed"),"Неизвестный статус предмета") }
   is Task -> { title(data.title);text(data.description);text(data.notes);links(data.links);url(data.resultUrl);requireValid(data.status in setOf("todo","in_progress","submitted","accepted","revision"),"Неизвестный статус задания") }
   is Debt -> { text(data.requirements);text(data.nextStep,1000);text(data.teacher,300);text(data.notes);text(data.confirmation);requireValid(data.reason in setOf("difference","overdue","retake"),"Неизвестная причина долга");requireValid(data.status in setOf("clarify","working","review","ready","closed"),"Неизвестный статус долга");requireValid(data.status!="closed" || (data.closedAt!=null && data.confirmation.isNotBlank()),"Для закрытия укажите дату и подтверждение результата");requireValid(data.status=="closed" || data.closedAt==null,"Дата закрытия допустима только у закрытого долга") }
   is Lesson -> { requireValid(data.weekday in 1..7,"День недели: от 1 до 7");requireValid(data.startTime!=data.endTime,"Начало и конец не должны совпадать");requireValid(!data.validUntil.isBefore(data.validFrom) && data.validUntil<=data.validFrom.plusYears(2),"Период расписания — не более двух лет");ZoneId.of(data.timezone);requireValid(data.weekOne.dayOfWeek==DayOfWeek.MONDAY,"Первая учебная неделя начинается в понедельник");requireValid(data.parity in setOf("all","even","odd"),"Неизвестное повторение");requireValid(data.type in setOf("lecture","practice","lab"),"Неизвестный тип занятия");url(data.onlineUrl);text(data.room,300) }
   is Note -> { requireValid(data.text.isNotBlank(),"Заметка пуста");text(data.text) }
  }
 }
}
