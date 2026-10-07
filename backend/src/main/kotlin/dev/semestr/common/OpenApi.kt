package dev.semestr.common

import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springdoc.core.customizers.OpenApiCustomizer
import io.swagger.v3.oas.models.info.Info
import io.swagger.v3.oas.models.media.*
import io.swagger.v3.oas.models.responses.ApiResponse
import io.swagger.v3.oas.models.security.*

@Configuration
class OpenApi {
 @Bean fun contract()=OpenApiCustomizer { api ->
  api.info=Info().title("Семестр API").version("1.0.0").description("REST API. Cookie sessions require X-CSRF-Token for mutations. Native clients may request a bearer token with native=true at login and must store it in the OS keychain. Dates of debts are calendar dates; task deadlines and occurrences are UTC instants. Record updates require version; conflicts return 409.")
  val schemas=api.components.schemas
  val kinds=mapOf("Subject" to "subject","Task" to "task","Debt" to "debt","Lesson" to "lesson","Note" to "note")
  kinds.forEach{(name,kind)->
   val schema=schemas[name]!!;val props=linkedMapOf<String,Schema<*>>();val required=mutableSetOf<String>()
   schema.properties?.let{props.putAll(it)};schema.required?.let{required.addAll(it)}
   schema.allOf?.forEach{part->part.properties?.let{props.putAll(it)};part.required?.let{required.addAll(it)}}
   schema.allOf=null;schema.type="object";schema.types=mutableSetOf("object");schema.properties=props;schema.addProperty("kind",StringSchema()._enum(listOf(kind)));schema.required=(required+"kind").toList()
  }
  schemas["StudyData"]=ComposedSchema().oneOf(kinds.keys.map{Schema<Any>().`$ref`("#/components/schemas/$it")}).discriminator(Discriminator().propertyName("kind").mapping(kinds.entries.associate{it.value to "#/components/schemas/${it.key}"}))
  schemas["ApiError"]=ObjectSchema().addProperty("code",StringSchema()).addProperty("message",StringSchema()).required(listOf("code","message"))
  api.components.addSecuritySchemes("session",SecurityScheme().type(SecurityScheme.Type.APIKEY).`in`(SecurityScheme.In.COOKIE).name("semestr_session"))
  api.components.addSecuritySchemes("bearer",SecurityScheme().type(SecurityScheme.Type.HTTP).scheme("bearer"))
  api.paths.forEach{(path,item)->item.readOperations().forEach{op->
   op.security=if(path.startsWith("/api/v1/auth/") && !path.endsWith("session") && !path.endsWith("logout"))emptyList() else listOf(SecurityRequirement().addList("session"),SecurityRequirement().addList("bearer"))
   mapOf("401" to "Session required","403" to "Forbidden / CSRF / email not verified","404" to "Owned record not found","409" to "Version or integrity conflict","422" to "Validation failed","429" to "Rate limit","503" to "Service unavailable").forEach{(code,desc)->op.responses.addApiResponse(code,ApiResponse().description(desc).content(Content().addMediaType("application/json",MediaType().schema(Schema<Any>().`$ref`("#/components/schemas/ApiError"))))) }
  }}
 }
}
