FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -B dependency:go-offline
COPY src src
RUN mvn -B package -DskipTests
FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S semestr && adduser -S semestr -G semestr
USER semestr
COPY --from=build /app/target/semestr-server-0.1.0.jar /app.jar
ENTRYPOINT ["java","-jar","/app.jar"]
