# REST API v1

Авторитетный контракт генерирует Springdoc: `GET /v3/api-docs`, интерфейс `/swagger-ui/index.html`. В репозитории сохранён `openapi.json`. Все бизнес-операции начинаются с `/api/v1`.

## Аутентификация

`POST /auth/register` с `{email,password}` создаёт неподтверждённый аккаунт и отправляет ссылку с 30-минутным одноразовым токеном. Пароль минимум 12 символов, максимум 72 UTF-8 байта (ограничение BCrypt). Ссылки используют фрагмент URL, не query: токен не попадает в стандартный HTTP access log. `POST /auth/verify` принимает `{token}`. Повторное письмо: `/auth/resend` с `{email}`.

`POST /auth/login` возвращает `{account,csrf}` и устанавливает `semestr_session` HttpOnly/SameSite=Lax cookie. Срок сессии — 14 дней, продление входом. В production cookie имеет Secure. Каждый изменяющий запрос с cookie отправляет `Content-Type: application/json` и `X-CSRF-Token`. Значение CSRF восстанавливается через `GET /auth/session`. Origin при наличии должен точно совпадать с APP_ORIGIN. CORS для произвольных origins не разрешается; веб и API должны иметь один origin.

Для отдельного нативного приложения укажите `native:true` при входе: ответ дополнительно содержит `accessToken`, cookie не устанавливается. Отправляйте `Authorization: Bearer <token>`. Токен хранится в Keychain/Keystore, никогда в JS localStorage. Bearer-запросу отдельный CSRF не нужен. Полный OAuth/OIDC и вращаемые refresh tokens пока не реализованы; после 14 дней нужен вход.

`POST /auth/logout` удаляет только текущую сессию. `/auth/forgot` отправляет письмо, `/auth/reset` принимает `{token,password}` и отзывает все сессии. Ответы регистрации/запроса письма не раскрывают наличие аккаунта. `/account/delete` с паролем удаляет аккаунт, все записи и сессии.

## Записи

`GET /records?kind=subject&limit=100&cursor=<uuid>` возвращает `{items,nextCursor}`. Limit 1–200; cursor непрозрачный для клиента, передавать только полученное значение. Без kind возвращаются все типы. Для расписания и полного экспорта есть отдельные endpoints.

```json
{
  "data": {
    "kind": "subject",
    "title": "Линейная алгебра",
    "assessment": "exam",
    "status": "studying"
  }
}
```

`POST /records` создаёт запись. `data.kind` — `subject`, `task`, `debt`, `lesson`, `note`; все поля описаны в OpenAPI. Неизвестные значения оставляют пустыми. Пустая строка и `unknown` соответствуют неуточнённым данным; nullable даты/ссылки на записи — `null`.

`PUT /records/{id}` требует `{version,data}`. `DELETE /records/{id}?version=0` также проверяет версию; отправляйте пустой JSON `{}`. После конфликта нельзя автоматически повторять старые изменения с новой версией: покажите пользователю актуальные данные и его черновик. GET/UPDATE/DELETE чужой записи возвращают 404. Связи проверяются по владельцу, типу и предмету. Изменение типа или subjectId существующей записи запрещено.

## Расписание

`GET /schedule?from=<UTC Instant>&until=<UTC Instant>` возвращает события, пересекающие полуоткрытый диапазон `[from, until)`, не более 62 дней. Время отдаётся в UTC, клиент показывает IANA timezone профиля. `conflict` указывает пересечение с другой парой.

`PUT /schedule/{lessonId}/exception` с `{originalDate}` отменяет одну пару; с `startsAt,endsAt` переносит. Для изменения существующего исключения нужен `version`. `GET /schedule/exceptions` возвращает исключения, включая отменённые пары. `DELETE /schedule/exceptions/{id}?version=...` восстанавливает исходную серию. Удаление серии удаляет её исключения.

## Импорт/экспорт

`GET /export` даёт `{formatVersion:1,profile,records,exceptions}` без пароля/email-токенов/сессий. Чтение — согласованный snapshot. `POST /import/preview` принимает bundle, полностью проверяет его и возвращает числа записей. `POST /import` принимает `{bundle,mode,expectedRevision,confirmed}`. Revision берётся из account до предпросмотра. `mode=replace` требует `confirmed=true`; при `add` профиль не заменяется. Максимум 5 МБ, 10 000 записей и 10 000 исключений в одном импорте.

## Ошибки

```json
{"code":"conflict","message":"Данные изменились на другом устройстве. Обновите страницу; ваш черновик сохранён."}
```

401 — сессия отсутствует/истекла; 403 — CSRF/Origin/неподтверждённый email; 404 — доступная запись не найдена; 409 — конфликт версии или связи; 422 — неверные данные; 429 — частые auth-запросы; 503 — временно недоступна почта. Текст ошибки подходит для интерфейса; ветвиться нужно по code/status.

Обновление контракта: запустите backend, сохраните `/v3/api-docs` в `docs/openapi.json`, выполните `pnpm api:generate`, затем `pnpm build`.
