# CinemaAbyss — C4 Architecture Overview

## System Context (C4 Level 1)

```
┌─────────────┐         ┌──────────────────────────────────────────┐         ┌─────────────────┐
│   Client    │  ───▶   │           CinemaAbyss System             │  ───▶   │  GHCR Registry  │
│  (Browser/  │  HTTP   │         Streaming Platform               │  Push   │  (CI/CD)        │
│   Mobile)   │         │                                          │         │                 │
└─────────────┘         └──────────────────────────────────────────┘         └─────────────────┘
```

**CinemaAbyss** — платформа для стриминга фильмов с управлением пользователями, подписками, платежами и каталогом контента.

---

## Containers (C4 Level 2)

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              CinemaAbyss System                                     │
│                                                                                     │
│  ┌──────────────────┐    ┌───────────────────┐    ┌──────────────────┐              │
│  │   Proxy Service  │    │     Monolith      │    │  Movies Service  │              │
│  │   (API Gateway)  │───▶│   (Go, :8080)     │◀──▶│   (Go, :8081)    │              │
│  │     (:8000)      │    │  Users, Payments, │    │  Movies CRUD     │              │
│  │  [NOT IMPL.]     │    │  Subscriptions    │    │  Strangled from  │              │
│  │                  │    │                   │    │  monolith        │              │
│  └────────┬─────────┘    └────────┬──────────┘    └────────┬─────────┘              │
│           │                       │                        │                        │
│           │                       │                        │                        │
│  ┌────────▼─────────┐    ┌────────▼────────────────────────▼─────────┐              │
│  │  Events Service  │    │              PostgreSQL 14                │              │
│  │   (Kafka-based)  │───▶│            (:5432, shared)                │              │
│  │   [NOT IMPL.]    │    │  Tables: users, movies, payments,         │              │
│  │                  │    │  subscriptions, views, user_ratings,      │              │
│  └────────┬─────────┘    │  movie_genres                             │              │
│           │              └───────────────────────────────────────────┘              │
│           │                                                                         │
│  ┌────────▼─────────┐    ┌──────────────────┐    ┌──────────────────┐               │
│  │      Kafka       │    │    ZooKeeper     │    │     Kafka UI     │               │
│  │   (:9092)        │◀──▶│    (:2181)       │    │    (:8090)       │               │
│  │  Topics:         │    │                  │    │                  │               │
│  │  - movie-events  │    └──────────────────┘    └──────────────────┘               │
│  │  - user-events   │                                                               │
│  │  - payment-events│                                                               │
│  └──────────────────┘                                                               │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Components (C4 Level 3)

### 1. Monolith (`src/monolith/`)

| Атрибут       | Значение          |
| ------------- | ----------------- |
| **Язык**      | Go 1.23           |
| **Фреймворк** | stdlib `net/http` |
| **Порт**      | 8080              |
| **Статус**    | ✅ Реализован     |

**Компоненты:**

- `UserHandler` — CRUD пользователей (`/api/users`)
- `MovieHandler` — CRUD фильмов (частично, мигрирует в микросервис)
- `PaymentHandler` — CRUD платежей (`/api/payments`)
- `SubscriptionHandler` — CRUD подписок (`/api/subscriptions`)
- `HealthHandler` — health check (`/health`)

### 2. Movies Microservice (`src/microservices/movies/`)

| Атрибут       | Значение          |
| ------------- | ----------------- |
| **Язык**      | Go 1.23           |
| **Фреймворк** | stdlib `net/http` |
| **Порт**      | 8081              |
| **Статус**    | ✅ Реализован     |
| **Паттерн**   | Strangler Fig     |

**Компоненты:**

- `MovieHandler` — CRUD фильмов (`/api/movies`), вынесен из монолита
- `HealthHandler` — health check (`/api/movies/health`)

### 3. Proxy Service / API Gateway (`src/microservices/proxy/`)

| Атрибут    | Значение                             |
| ---------- | ------------------------------------ |
| **Порт**   | 8000                                 |
| **Статус** | ❌ НЕ реализован (только `.gitkeep`) |

**Планируемые компоненты:**

- Маршрутизация запросов между монолитом и микросервисами
- Постепенная миграция трафика через `GRADUAL_MIGRATION` и `MOVIES_MIGRATION_PERCENT`

### 4. Events Service (`src/microservices/events/`)

| Атрибут    | Значение                          |
| ---------- | --------------------------------- |
| **Порт**   | 8082                              |
| **Статус** | ❌ НЕ реализован (исходников нет) |

**Планируемые компоненты:**

- Потребление событий из Kafka (`movie-events`, `user-events`, `payment-events`)
- Публикация событий от всех сервисов

---

## Code (C4 Level 4) — Ключевые файлы

| Компонент          | Файлы                                                                                                                |
| ------------------ | -------------------------------------------------------------------------------------------------------------------- |
| **Monolith**       | `src/monolith/main.go`, `src/monolith/handlers.go`, `src/monolith/Dockerfile`                                        |
| **Movies Service** | `src/microservices/movies/main.go`, `src/microservices/movies/handlers.go`, `src/microservices/movies/Dockerfile`    |
| **Database**       | `src/database/init.sql`                                                                                              |
| **API Spec**       | `api-specification.yaml` (OpenAPI 3.0.3)                                                                             |
| **Docker Compose** | `docker-compose.yml`                                                                                                 |
| **Kubernetes**     | `src/kubernetes/deployments/`, `src/kubernetes/services/`, `src/kubernetes/statefulsets/`, `src/kubernetes/ingress/` |
| **Helm Chart**     | `src/kubernetes/helm/`                                                                                               |
| **CI/CD**          | `.github/workflows/docker-build-push.yml`, `.github/workflows/api-tests.yml`                                         |
| **Tests**          | `tests/postman/` (Newman)                                                                                            |

---

## Технологии

| Компонент            | Технология                          | Версия     |
| -------------------- | ----------------------------------- | ---------- |
| **Monolith**         | Go, stdlib net/http, lib/pq         | 1.23       |
| **Movies Service**   | Go, stdlib net/http, lib/pq         | 1.23       |
| **Database**         | PostgreSQL                          | 14         |
| **Message Broker**   | Kafka                               | 2.13-2.7.0 |
| **Coordination**     | ZooKeeper                           | latest     |
| **Orchestration**    | Kubernetes                          | v1.19+     |
| **Package Mgmt**     | Helm                                | v3.2.0+    |
| **Ingress**          | NGINX                               | —          |
| **CI/CD**            | GitHub Actions, Docker Buildx, GHCR | —          |
| **API Testing**      | Node.js, Newman, Postman            | v14+       |
| **Kafka Monitoring** | Kafka UI (provectuslabs)            | latest     |

---

## Взаимодействие компонентов

### Синхронное (HTTP/REST)

```
Client → Proxy (:8000) → [Monolith (:8080) | Movies Service (:8081)]
```

### Асинхронное (Kafka)

```
Service → Kafka (:9092) → Topics: movie-events, user-events, payment-events → Events Service
```

### База данных (shared)

```
Monolith ──┐
           └──→ PostgreSQL (:5432, db: cinemaabyss)
Movies ────┘
```

---

## Ключевые наблюдения

1. **Strangler Fig Pattern** — постепенная миграция из монолита в микросервисы через прокси-шлюз.
2. **Неполная реализация** — Proxy Service и Events Service существуют только в конфигурациях (Docker Compose, K8s, Helm), исходного кода нет.
3. **Shared Database** — монолит и movies service используют одну БД PostgreSQL, что создаёт coupling (типично для ранней стадии миграции).
4. **Kafka topics** — три топика с 1 партицией и RF=1: `movie-events`, `user-events`, `payment-events`.
5. **Container Registry** — образы публикуются в GHCR: `ghcr.io/db-exp/cinemaabysstest/`.
