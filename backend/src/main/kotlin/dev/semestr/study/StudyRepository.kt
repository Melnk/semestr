package dev.semestr.study

import com.fasterxml.jackson.databind.ObjectMapper
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Repository
import java.util.UUID
import dev.semestr.common.ApiException

@Repository
class StudyRepository(val db:JdbcTemplate,val json:ObjectMapper) {
 private val mapper=org.springframework.jdbc.core.RowMapper { r:java.sql.ResultSet,_:Int -> StudyRecord(r.getObject("id",UUID::class.java),r.getLong("version"),json.readValue(r.getString("payload"),StudyData::class.java)) }
 fun lock(user:UUID)=db.queryForObject("SELECT revision FROM accounts WHERE id=? FOR UPDATE",Long::class.java,user)!!
 fun bump(user:UUID) { db.update("UPDATE accounts SET revision=revision+1 WHERE id=?",user) }
 fun get(user:UUID,id:UUID)=db.query("SELECT * FROM study_records WHERE user_id=? AND id=?",mapper,user,id).firstOrNull() ?: throw ApiException(404,"not_found","Запись не найдена")
 fun all(user:UUID)=db.query("SELECT * FROM study_records WHERE user_id=? ORDER BY id",mapper,user)
 fun page(user:UUID,kind:String?,cursor:UUID?,limit:Int):RecordPage {
  val rows=db.query("SELECT * FROM study_records WHERE user_id=? AND (?::text IS NULL OR kind=?) AND (?::uuid IS NULL OR id>?) ORDER BY id LIMIT ?",mapper,user,kind,kind,cursor,cursor,limit+1)
  return RecordPage(rows.take(limit),if(rows.size>limit)rows[limit-1].id else null)
 }
 fun save(user:UUID,id:UUID,data:StudyData,version:Long?):StudyRecord {
  val payload=json.writerFor(StudyData::class.java).writeValueAsString(data)
  val debt=(data as? Task)?.debtId;val lesson=(data as? Task)?.lessonId
  if(version==null) db.update("INSERT INTO study_records(id,user_id,kind,subject_id,debt_id,lesson_id,payload) VALUES (?,?,?,?,?,?,?::jsonb)",id,user,data.kind(),data.subjectId(),debt,lesson,payload)
  else if(db.update("UPDATE study_records SET subject_id=?,debt_id=?,lesson_id=?,payload=?::jsonb,version=version+1,updated_at=now() WHERE user_id=? AND id=? AND version=?",data.subjectId(),debt,lesson,payload,user,id,version)!=1) throw ApiException(409,"conflict","Данные изменились на другом устройстве. Обновите страницу; ваш черновик сохранён.")
  bump(user);return get(user,id)
 }
 fun exceptions(user:UUID)=db.query("SELECT * FROM lesson_exceptions WHERE user_id=?",{r,_ -> ExceptionData(r.getObject("id",UUID::class.java),r.getObject("lesson_id",UUID::class.java),r.getDate("original_date").toLocalDate(),r.getTimestamp("starts_at")?.toInstant(),r.getTimestamp("ends_at")?.toInstant(),r.getLong("version"))},user)
}
