#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_DIR="$PWD"
RUNTIME_DIR="$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies"
if ! command -v node >/dev/null 2>&1 && [ -x "$RUNTIME_DIR/node/bin/node" ]; then
  export PATH="$RUNTIME_DIR/node/bin:$RUNTIME_DIR/bin/fallback:$PATH"
fi
export PATH="/opt/homebrew/bin:$PATH"
if [ -d /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home ]; then
  export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
fi
for executable in node pnpm java mvn docker curl; do
  command -v "$executable" >/dev/null 2>&1 || { echo "Нужен $executable — см. README."; exit 1; }
done
mkdir -p .local
if ! docker info >/dev/null 2>&1 && [ -S "$HOME/.colima/default/docker.sock" ]; then
  export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
fi
docker info >/dev/null 2>&1 || { echo 'Запустите Docker Desktop или Colima и повторите.'; exit 1; }
if docker container inspect semestr-db >/dev/null 2>&1; then docker start semestr-db >/dev/null; else
  docker run -d --name semestr-db --label semestr.local=true -e POSTGRES_DB=semestr -e POSTGRES_USER=semestr -e POSTGRES_PASSWORD=local-development-only -p 127.0.0.1:54329:5432 -v semestr-data:/var/lib/postgresql/data postgres:17-alpine >/dev/null
fi
if docker container inspect semestr-mail >/dev/null 2>&1; then docker start semestr-mail >/dev/null; else
  docker run -d --name semestr-mail --label semestr.local=true -p 127.0.0.1:1025:1025 -p 127.0.0.1:8025:8025 axllent/mailpit:v1.29 >/dev/null
fi
for attempt in $(seq 1 30); do
  if docker exec semestr-db pg_isready -U semestr >/dev/null 2>&1; then break; fi
  sleep 1
done
SERVER_PID=''
WEB_PID=''
cleanup() {
  if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null || true; fi
  if [ -n "$WEB_PID" ]; then kill "$WEB_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT INT TERM
if ! curl -fsS http://localhost:8080/v3/api-docs 2>/dev/null | grep 'Семестр API' >/dev/null; then
  mvn -f backend/pom.xml -Dmaven.repo.local="$PROJECT_DIR/.local/m2" -q package
  java -jar backend/target/semestr-server-0.1.0.jar > .local/server.log 2>&1 &
  SERVER_PID=$!
fi
for attempt in $(seq 1 30); do
  if curl -fsS http://localhost:8080/actuator/health >/dev/null 2>&1; then break; fi
  sleep 1
done
curl -fsS http://localhost:8080/actuator/health >/dev/null || { echo 'Сервер не запущен; см. .local/server.log'; exit 1; }
if ! curl -fsS http://localhost:5173 2>/dev/null | grep 'Семестр' >/dev/null; then
  pnpm install --frozen-lockfile
  pnpm dev &
  WEB_PID=$!
fi
echo 'Семестр: http://localhost:5173 — письма: http://localhost:8025'
if [ -n "$WEB_PID" ]; then wait "$WEB_PID"; elif [ -n "$SERVER_PID" ]; then wait "$SERVER_PID"; fi
