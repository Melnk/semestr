package dev.semestr.study

import dev.semestr.common.*
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.util.UUID

@Service
class StudyService(val repo:StudyRepository) {
 fun validateRelations(user:UUID,data:StudyData,records:Map<UUID,StudyRecord>?=null) {
  fun get(id:UUID)=if(records!=null) records[id] ?: throw ApiException(422,"reference","Отсутствует связанная запись") else repo.get(user,id)
  data.subjectId()?.let { requireValid(get(it).data is Subject,"Связь должна вести на предмет") }
  if(data is Task) {
   data.debtId?.let { val d=get(it).data;requireValid(d is Debt && d.subjectId==data.subjectId,"Долг должен относиться к этому предмету") }
   data.lessonId?.let { val d=get(it).data;requireValid(d is Lesson && d.subjectId==data.subjectId,"Занятие должно относиться к этому предмету") }
  }
 }
 @Transactional
 fun create(user:UUID,data:StudyData):StudyRecord {repo.lock(user);Rules.validate(data);validateRelations(user,data);return repo.save(user,UUID.randomUUID(),data,null)}
 @Transactional
 fun update(user:UUID,id:UUID,request:WriteRecord):StudyRecord {
  repo.lock(user);val old=repo.get(user,id);requireValid(request.version!=null,"Укажите версию записи");requireValid(old.data.kind()==request.data.kind(),"Нельзя изменить тип записи");Rules.validate(request.data);validateRelations(user,request.data)
  requireValid(old.data.subjectId()==request.data.subjectId(),"Принадлежность предмету нельзя менять; создайте новую запись")
  if(request.data is Lesson) requireValid(repo.exceptions(user).filter{it.lessonId==id}.all{dev.semestr.schedule.Recurrence.matches(request.data,it.originalDate)},"Сначала восстановите исключения, которые не входят в новое расписание")
  return repo.save(user,id,request.data,request.version)
 }
 @Transactional
 fun delete(user:UUID,id:UUID,version:Long) {
  repo.lock(user);repo.get(user,id)
  if(repo.db.update("DELETE FROM study_records WHERE user_id=? AND id=? AND version=?",user,id,version)!=1)throw ApiException(409,"conflict","Запись изменена на другом устройстве")
  repo.bump(user)
 }
}
