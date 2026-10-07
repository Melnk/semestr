package dev.semestr.study

import com.fasterxml.jackson.annotation.*
import java.time.*
import java.util.UUID
import io.swagger.v3.oas.annotations.media.Schema

data class Link(val title: String, val url: String)
@JsonTypeInfo(use=JsonTypeInfo.Id.NAME, include=JsonTypeInfo.As.PROPERTY, property="kind")
@JsonSubTypes(JsonSubTypes.Type(Subject::class,name="subject"), JsonSubTypes.Type(Task::class,name="task"), JsonSubTypes.Type(Debt::class,name="debt"), JsonSubTypes.Type(Lesson::class,name="lesson"), JsonSubTypes.Type(Note::class,name="note"))
@Schema(oneOf=[Subject::class,Task::class,Debt::class,Lesson::class,Note::class],discriminatorProperty="kind")
sealed interface StudyData
data class Subject(val title:String, val semester:String="", val description:String="", val teacher:String="", val contact:String="", val assessment:String="unknown", val requirements:String="", val admission:String="", val onlineUrl:String="", val links:List<Link> = emptyList(), val status:String="studying"): StudyData
data class Task(val subjectId:UUID, val title:String, val description:String="", val deadline:Instant?=null, val status:String="todo", val debtId:UUID?=null, val lessonId:UUID?=null, val links:List<Link> = emptyList(), val resultUrl:String="", val notes:String=""): StudyData
data class Debt(val subjectId:UUID, val reason:String="difference", val deadline:LocalDate?=null, val requirements:String="", val nextStep:String="", val teacher:String="", val status:String="clarify", val closedAt:LocalDate?=null, val confirmation:String="", val notes:String=""): StudyData
data class Lesson(val subjectId:UUID, val weekday:Int, val startTime:LocalTime, val endTime:LocalTime, val type:String="practice", val validFrom:LocalDate, val validUntil:LocalDate, val timezone:String, val parity:String="all", val weekOne:LocalDate, val onlineUrl:String="", val room:String=""): StudyData
data class Note(val subjectId:UUID, val text:String): StudyData
data class StudyRecord(val id:UUID, val version:Long, val data:StudyData)
data class WriteRecord(val version:Long?=null, val data:StudyData)
data class RecordPage(val items:List<StudyRecord>, val nextCursor:UUID?)
data class ExceptionData(val id:UUID, val lessonId:UUID, val originalDate:LocalDate, val startsAt:Instant?, val endsAt:Instant?, val version:Long=0)
data class ExceptionWrite(val originalDate:LocalDate, val startsAt:Instant?=null, val endsAt:Instant?=null, val version:Long?=null)
data class Occurrence(val lessonId:UUID,val subjectId:UUID,val title:String,val startsAt:Instant,val endsAt:Instant,val onlineUrl:String,val room:String,val type:String,val originalDate:LocalDate,val changed:Boolean=false,val conflict:Boolean=false)
fun StudyData.kind()=when(this){is Subject->"subject";is Task->"task";is Debt->"debt";is Lesson->"lesson";is Note->"note"}
fun StudyData.subjectId():UUID?=when(this){is Subject->null;is Task->subjectId;is Debt->subjectId;is Lesson->subjectId;is Note->subjectId}
