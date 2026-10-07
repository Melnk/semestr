package dev.semestr.study

import dev.semestr.accounts.user
import dev.semestr.schedule.ScheduleService
import dev.semestr.transfer.*
import jakarta.servlet.http.HttpServletRequest
import org.springframework.web.bind.annotation.*
import java.util.UUID
import java.time.Instant
import dev.semestr.common.requireValid

@RestController
@RequestMapping("/api/v1")
class StudyController(val service:StudyService,val schedule:ScheduleService,val transfer:TransferService) {
 @GetMapping("/records") fun list(req:HttpServletRequest,@RequestParam(required=false)kind:String?,@RequestParam(required=false)cursor:UUID?,@RequestParam(defaultValue="100")limit:Int):RecordPage {requireValid(limit in 1..200,"Размер страницы от 1 до 200");return service.repo.page(user(req),kind,cursor,limit)}
 @PostMapping("/records") fun create(req:HttpServletRequest,@RequestBody body:WriteRecord)=service.create(user(req),body.data)
 @GetMapping("/records/{id}") fun get(req:HttpServletRequest,@PathVariable id:UUID)=service.repo.get(user(req),id)
 @PutMapping("/records/{id}") fun update(req:HttpServletRequest,@PathVariable id:UUID,@RequestBody body:WriteRecord)=service.update(user(req),id,body)
 @DeleteMapping("/records/{id}") fun delete(req:HttpServletRequest,@PathVariable id:UUID,@RequestParam version:Long)=service.delete(user(req),id,version)
 @GetMapping("/schedule") fun schedule(req:HttpServletRequest,@RequestParam from:Instant,@RequestParam until:Instant)=schedule.occurrences(user(req),from,until)
 @GetMapping("/schedule/exceptions") fun exceptions(req:HttpServletRequest)=service.repo.exceptions(user(req))
 @DeleteMapping("/schedule/exceptions/{id}") fun restore(req:HttpServletRequest,@PathVariable id:UUID,@RequestParam version:Long)=schedule.restore(user(req),id,version)
 @PutMapping("/schedule/{id}/exception") fun exception(req:HttpServletRequest,@PathVariable id:UUID,@RequestBody body:ExceptionWrite)=schedule.exception(user(req),id,body)
 @GetMapping("/export") fun export(req:HttpServletRequest)=transfer.export(user(req))
 @PostMapping("/import/preview") fun preview(req:HttpServletRequest,@RequestBody body:ExportBundle)=transfer.validate(user(req),body)
 @PostMapping("/import") fun import(req:HttpServletRequest,@RequestBody body:ImportRequest)=transfer.apply(user(req),body)
}
