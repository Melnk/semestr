package dev.semestr.accounts

import com.fasterxml.jackson.databind.ObjectMapper
import dev.semestr.common.*
import jakarta.servlet.FilterChain
import jakarta.servlet.http.*
import org.springframework.beans.factory.annotation.Value
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Component
import org.springframework.stereotype.Service
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.filter.OncePerRequestFilter
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.*
import java.time.*
import org.springframework.mail.SimpleMailMessage
import org.springframework.mail.javamail.JavaMailSender

fun token():String=ByteArray(32).also{SecureRandom().nextBytes(it)}.let{Base64.getUrlEncoder().withoutPadding().encodeToString(it)}
fun digest(value:String)=MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString(""){"%02x".format(it)}
fun user(request:HttpServletRequest)=request.getAttribute("user") as UUID
data class Profile(val name:String="",val university:String="",val direction:String="",val group:String="",val timezone:String="Europe/Moscow",val semester:String="",val weekOne:LocalDate=LocalDate.now().with(java.time.DayOfWeek.MONDAY),val onboarded:Boolean=false)
data class AccountView(val id:UUID,val email:String,val profile:Profile,val version:Long,val revision:Long)
data class SessionView(val account:AccountView,val csrf:String,val accessToken:String?=null)
data class Credentials(val email:String,val password:String,val native:Boolean=false)
data class EmailRequest(val email:String)
data class TokenRequest(val token:String,val password:String?=null)
data class ProfileWrite(val version:Long,val profile:Profile)
data class DeleteAccount(val password:String)

@Service
class AuthService(val db:JdbcTemplate,val json:ObjectMapper,val mail:JavaMailSender,@Value("\${semestr.origin}")val origin:String,@Value("\${semestr.mail-from}")val from:String) {
 val passwords=BCryptPasswordEncoder(12)
 private val dummy=passwords.encode("dummy-password-never-used")
 fun rate(key:String) {
  val count=db.queryForObject("INSERT INTO rate_limits(key,count,expires_at) VALUES (?,1,now()+interval '15 minutes') ON CONFLICT(key) DO UPDATE SET count=CASE WHEN rate_limits.expires_at<now() THEN 1 ELSE rate_limits.count+1 END, expires_at=CASE WHEN rate_limits.expires_at<now() THEN now()+interval '15 minutes' ELSE rate_limits.expires_at END RETURNING count",Int::class.java,key)!!
  if(count>20)throw ApiException(429,"rate_limit","Слишком много попыток. Попробуйте через 15 минут.")
 }
 fun password(value:String) {requireValid(value.length>=12 && value.toByteArray().size<=72,"Пароль: от 12 символов и не более 72 байт")}
 fun email(value:String):String {val e=value.trim().lowercase();requireValid(e.length<=254 && Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$").matches(e),"Проверьте email");return e}
 fun account(id:UUID)=db.query("SELECT * FROM accounts WHERE id=?",{r,_->AccountView(id,r.getString("email"),json.readValue(r.getString("profile"),Profile::class.java),r.getLong("version"),r.getLong("revision"))},id).first()
 @Transactional
 fun register(body:Credentials) {
  val e=email(body.email);password(body.password)
  if(db.queryForObject("SELECT count(*) FROM accounts WHERE email=?",Int::class.java,e)!!>0)return
  val id=UUID.randomUUID();db.update("INSERT INTO accounts(id,email,password_hash,profile) VALUES (?,?,?,?::jsonb)",id,e,passwords.encode(body.password),json.writeValueAsString(Profile()))
  sendToken(id,e,"verify")
 }
 fun sendToken(id:UUID,email:String,purpose:String) {
  val t=token();db.update("DELETE FROM email_tokens WHERE user_id=? AND purpose=?",id,purpose)
  db.update("INSERT INTO email_tokens(token_hash,user_id,purpose,expires_at) VALUES (?,?,?,now()+interval '30 minutes')",digest(t),id,purpose)
  val message=SimpleMailMessage();message.setFrom(from);message.setTo(email);message.subject=if(purpose=="verify")"Подтвердите почту — Семестр" else "Восстановление доступа — Семестр"
  message.text="Откройте ссылку в течение 30 минут:\n$origin/#$purpose=$t\nЕсли вы не запрашивали письмо, просто проигнорируйте его."
  try{mail.send(message)}catch(e:Exception){throw ApiException(503,"mail_unavailable","Почта временно недоступна. Попробуйте позже.")}
 }
 @Transactional
 fun requestEmail(e:String,purpose:String) {val rows=db.query("SELECT id,verified FROM accounts WHERE email=?",{r,_->r.getObject("id",UUID::class.java) to r.getBoolean("verified")},email(e));rows.firstOrNull()?.let{if(purpose=="reset" || !it.second)sendToken(it.first,email(e),purpose)}}
 @Transactional
 fun redeem(body:TokenRequest,purpose:String) {
  val ids=db.query("DELETE FROM email_tokens WHERE token_hash=? AND purpose=? AND expires_at>now() RETURNING user_id",{r,_->r.getObject(1,UUID::class.java)},digest(body.token),purpose)
  val id=ids.firstOrNull()?:throw ApiException(422,"invalid_token","Ссылка недействительна или устарела")
  if(purpose=="verify")db.update("UPDATE accounts SET verified=true WHERE id=?",id)
  else {val p=body.password?:"";password(p);db.update("UPDATE accounts SET password_hash=? WHERE id=?",passwords.encode(p),id);db.update("DELETE FROM sessions WHERE user_id=?",id)}
 }
 @Transactional
 fun login(body:Credentials):Pair<String,SessionView> {
  val rows=db.query("SELECT id,password_hash,verified FROM accounts WHERE email=? FOR UPDATE",{r,_->Triple(r.getObject("id",UUID::class.java),r.getString("password_hash"),r.getBoolean("verified"))},email(body.email));val row=rows.firstOrNull()
  if(!passwords.matches(body.password,row?.second?:dummy) || row==null)throw ApiException(401,"credentials","Неверный email или пароль")
  if(!row.third)throw ApiException(403,"unverified","Подтвердите email по ссылке в письме")
  val t=token();val csrf=token();db.update("INSERT INTO sessions(token_hash,user_id,csrf,expires_at) VALUES (?,?,?,now()+interval '14 days')",digest(t),row.first,csrf)
  db.update("DELETE FROM sessions WHERE expires_at<now()")
  return t to SessionView(account(row.first),csrf,if(body.native)t else null)
 }
 @Transactional
 fun profile(id:UUID,body:ProfileWrite):AccountView {ZoneId.of(body.profile.timezone);requireValid(body.profile.weekOne.dayOfWeek==DayOfWeek.MONDAY,"Учебная неделя начинается в понедельник");requireValid(listOf(body.profile.name,body.profile.university,body.profile.direction,body.profile.group,body.profile.semester).all{it.length<=300},"Слишком длинное поле профиля");if(db.update("UPDATE accounts SET profile=?::jsonb,version=version+1,revision=revision+1 WHERE id=? AND version=?",json.writeValueAsString(body.profile),id,body.version)!=1)throw ApiException(409,"conflict","Профиль изменён на другом устройстве");return account(id)}
 @Transactional
 fun delete(id:UUID,password:String) {val hash=db.queryForObject("SELECT password_hash FROM accounts WHERE id=? FOR UPDATE",String::class.java,id);if(!passwords.matches(password,hash))throw ApiException(403,"credentials","Неверный пароль");db.update("DELETE FROM accounts WHERE id=?",id)}
}

@Component
class SessionFilter(val db:JdbcTemplate,val json:ObjectMapper,@Value("\${semestr.origin}")val origin:String):OncePerRequestFilter() {
 override fun doFilterInternal(req:HttpServletRequest,res:HttpServletResponse,chain:FilterChain) {
  res.setHeader("X-Content-Type-Options","nosniff");res.setHeader("Referrer-Policy","no-referrer")
  if(!req.requestURI.startsWith("/api/v1/")){chain.doFilter(req,res);return}
  res.setHeader("Cache-Control","no-store")
  try {
   val mutation=req.method !in setOf("GET","HEAD","OPTIONS")
   if(mutation && req.getHeader("Origin")!=null && req.getHeader("Origin")!=origin)throw ApiException(403,"origin","Недопустимый источник запроса")
   if(mutation && (req.contentLengthLong>5_000_000 || (req.contentType?.startsWith("application/json")!=true)))throw ApiException(415,"content_type","Ожидается JSON, не более 5 МБ")
   val public=setOf("/api/v1/auth/register","/api/v1/auth/login","/api/v1/auth/forgot","/api/v1/auth/resend","/api/v1/auth/verify","/api/v1/auth/reset")
   if(req.requestURI in public){chain.doFilter(req,res);return}
   val bearer=req.getHeader("Authorization")?.takeIf{it.startsWith("Bearer ")}?.removePrefix("Bearer ")
   val t=bearer ?: req.cookies?.firstOrNull{it.name=="semestr_session"}?.value ?: throw ApiException(401,"unauthorized","Войдите в аккаунт")
   val rows=db.query("SELECT user_id,csrf FROM sessions WHERE token_hash=? AND expires_at>now()",{r,_->r.getObject("user_id",UUID::class.java) to r.getString("csrf")},digest(t))
   val session=rows.firstOrNull()?:throw ApiException(401,"unauthorized","Сессия завершена. Войдите снова.")
   if(mutation && bearer==null && !MessageDigest.isEqual(session.second.toByteArray(),(req.getHeader("X-CSRF-Token")?:"").toByteArray()))throw ApiException(403,"csrf","Обновите страницу и повторите действие")
   req.setAttribute("user",session.first);req.setAttribute("csrf",session.second);req.setAttribute("session",digest(t));chain.doFilter(req,res)
  }catch(e:ApiException){res.status=e.status;res.contentType="application/json";json.writeValue(res.outputStream,ApiError(e.code,e.message))}
 }
}
