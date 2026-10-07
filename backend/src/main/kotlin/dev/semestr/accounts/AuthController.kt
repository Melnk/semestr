package dev.semestr.accounts

import jakarta.servlet.http.*
import org.springframework.web.bind.annotation.*
import org.springframework.http.ResponseCookie
import org.springframework.beans.factory.annotation.Value

@RestController
@RequestMapping("/api/v1")
class AuthController(val auth:AuthService,@Value("\${semestr.secure-cookie}")val secure:Boolean) {
 fun cookie(value:String,age:Long)=ResponseCookie.from("semestr_session",value).httpOnly(true).secure(secure).sameSite("Lax").path("/api").maxAge(age).build().toString()
 fun rate(req:HttpServletRequest,email:String) {auth.rate("ip:"+req.remoteAddr);auth.rate("email:"+digest(email.trim().lowercase()))}
 @PostMapping("/auth/register") fun register(@RequestBody body:Credentials,req:HttpServletRequest):Map<String,String> {rate(req,body.email);auth.register(body);return mapOf("message" to "Если регистрация возможна, письмо с подтверждением отправлено.")}
 @PostMapping("/auth/login") fun login(@RequestBody body:Credentials,req:HttpServletRequest,res:HttpServletResponse):SessionView {rate(req,body.email);val(t,s)=auth.login(body);if(!body.native)res.addHeader("Set-Cookie",cookie(t,1209600));return s}
 @PostMapping("/auth/forgot") fun forgot(@RequestBody body:EmailRequest,req:HttpServletRequest):Map<String,String> {rate(req,body.email);auth.requestEmail(body.email,"reset");return mapOf("message" to "Если аккаунт существует, письмо отправлено.")}
 @PostMapping("/auth/resend") fun resend(@RequestBody body:EmailRequest,req:HttpServletRequest):Map<String,String> {rate(req,body.email);auth.requestEmail(body.email,"verify");return mapOf("message" to "Если подтверждение требуется, письмо отправлено.")}
 @PostMapping("/auth/verify") fun verify(@RequestBody body:TokenRequest,req:HttpServletRequest) {auth.rate("token:"+req.remoteAddr);auth.redeem(body,"verify")}
 @PostMapping("/auth/reset") fun reset(@RequestBody body:TokenRequest,req:HttpServletRequest) {auth.rate("token:"+req.remoteAddr);auth.redeem(body,"reset")}
 @GetMapping("/auth/session") fun session(req:HttpServletRequest)=SessionView(auth.account(user(req)),req.getAttribute("csrf") as String)
 @PostMapping("/auth/logout") fun logout(req:HttpServletRequest,res:HttpServletResponse) {auth.db.update("DELETE FROM sessions WHERE token_hash=?",req.getAttribute("session"));res.addHeader("Set-Cookie",cookie("",0))}
 @PutMapping("/profile") fun profile(@RequestBody body:ProfileWrite,req:HttpServletRequest)=auth.profile(user(req),body)
 @PostMapping("/account/delete") fun delete(@RequestBody body:DeleteAccount,req:HttpServletRequest,res:HttpServletResponse) {auth.delete(user(req),body.password);res.addHeader("Set-Cookie",cookie("",0))}
}
