package dev.semestr.common

import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.*
import org.springframework.web.bind.MethodArgumentNotValidException
import org.springframework.http.converter.HttpMessageNotReadableException
import org.springframework.dao.DataIntegrityViolationException

class ApiException(val status: Int, val code: String, override val message: String): RuntimeException(message)
data class ApiError(val code: String, val message: String)
fun requireValid(condition: Boolean, message: String) { if (!condition) throw ApiException(422,"validation",message) }
@RestControllerAdvice
class Errors {
 private val log=org.slf4j.LoggerFactory.getLogger(Errors::class.java)
 @ExceptionHandler(Exception::class)
 fun unexpected(e:Exception):ResponseEntity<ApiError> {log.error("Request failed: {}",e.javaClass.simpleName);return ResponseEntity.status(500).body(ApiError("server_error","Сервер не смог выполнить запрос. Попробуйте позже."))}
 @ExceptionHandler(org.springframework.web.method.annotation.MethodArgumentTypeMismatchException::class,org.springframework.web.bind.MissingServletRequestParameterException::class)
 fun parameters(e:Exception)=ResponseEntity.status(422).body(ApiError("validation","Проверьте параметры запроса"))
 @ExceptionHandler(ApiException::class)
 fun known(e: ApiException) = ResponseEntity.status(e.status).body(ApiError(e.code,e.message))
 @ExceptionHandler(MethodArgumentNotValidException::class, HttpMessageNotReadableException::class, IllegalArgumentException::class)
 fun invalid(e: Exception) = ResponseEntity.status(422).body(ApiError("validation","Проверьте формат и обязательные поля"))
 @ExceptionHandler(DataIntegrityViolationException::class)
 fun integrity(e: Exception) = ResponseEntity.status(409).body(ApiError("conflict","Запись связана с другими данными или уже существует"))
}
