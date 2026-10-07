package dev.semestr

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*
import dev.semestr.study.*
import dev.semestr.schedule.Recurrence
import dev.semestr.common.ApiException
import java.time.*
import java.util.UUID

class RulesTest {
 private fun lesson(zone:String="Europe/Berlin",start:String="09:00",end:String="10:30",parity:String="all")=Lesson(UUID.randomUUID(),7,LocalTime.parse(start),LocalTime.parse(end),validFrom=LocalDate.parse("2026-01-01"),validUntil=LocalDate.parse("2026-12-31"),timezone=zone,parity=parity,weekOne=LocalDate.parse("2025-12-29"))
 @Test fun `DST changes instant while local class time stays fixed`() {val l=lesson();assertEquals(Instant.parse("2026-03-22T08:00:00Z"),Recurrence.times(l,LocalDate.parse("2026-03-22")).first);assertEquals(Instant.parse("2026-03-29T07:00:00Z"),Recurrence.times(l,LocalDate.parse("2026-03-29")).first)}
 @Test fun `night class crosses the local date boundary`() {val (s,e)=Recurrence.times(lesson("Asia/Tokyo","23:30","01:00"),LocalDate.parse("2026-10-04"));assertEquals(90,Duration.between(s,e).toMinutes());assertEquals(Instant.parse("2026-10-04T16:00:00Z"),e)}
 @Test fun `parity is based on user week one not calendar week`() {val l=lesson(parity="odd");assertTrue(Recurrence.matches(l,LocalDate.parse("2026-01-04")));assertFalse(Recurrence.matches(l,LocalDate.parse("2026-01-11")));assertFalse(Recurrence.matches(l,LocalDate.parse("2026-01-05")))}
 @Test fun `DST gap uses Java forward adjustment and overlap uses earlier offset`() {assertEquals(Instant.parse("2026-03-29T01:30:00Z"),Recurrence.times(lesson(start="02:30",end="04:00"),LocalDate.parse("2026-03-29")).first);assertEquals(Instant.parse("2026-10-25T00:30:00Z"),Recurrence.times(lesson(start="02:30",end="04:00"),LocalDate.parse("2026-10-25")).first)}
 @Test fun `closed debt requires confirmation and closure date`() {assertThrows(ApiException::class.java){Rules.validate(Debt(UUID.randomUUID(),status="closed"))};assertDoesNotThrow{Rules.validate(Debt(UUID.randomUUID(),status="closed",closedAt=LocalDate.now(),confirmation="Принято преподавателем"))}}
 @Test fun `task states remain distinct`() {for(s in listOf("todo","in_progress","submitted","accepted","revision"))assertDoesNotThrow{Rules.validate(Task(UUID.randomUUID(),"Работа",status=s))};assertThrows(ApiException::class.java){Rules.validate(Task(UUID.randomUUID(),"Работа",status="done"))}}
 @Test fun `unsafe links and credentials in URLs are rejected`() {for(u in listOf("javascript:alert(1)","file:///tmp/a","https://user:password@example.com"))assertThrows(ApiException::class.java){Rules.url(u)};assertDoesNotThrow{Rules.url("https://example.com/course")}}
 @Test fun `timezone and schedule bounds are validated`() {assertThrows(Exception::class.java){Rules.validate(lesson().copy(timezone="UTC+99"))};assertThrows(ApiException::class.java){Rules.validate(lesson().copy(validUntil=LocalDate.parse("2025-12-31")))};assertThrows(ApiException::class.java){Rules.validate(lesson().copy(weekOne=LocalDate.parse("2026-01-01")))}}
}
