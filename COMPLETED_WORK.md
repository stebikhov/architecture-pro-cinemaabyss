# Выполненные задания - CinemaAbyss Architecture

## Задание 1: Проектирование To-Be архитектуры ✅

### Созданные файлы:
- `docs/architecture/to-be-architecture.md` - Полное описание To-Be архитектуры
- `docs/architecture/container-diagram.puml` - C4 контейнерная диаграмма (PlantUML)

### Краткое описание:
- Система разделена на 6 доменов: Users, Movies, Payments, Subscriptions, Events, API Gateway
- Единая точка входа: Proxy Service (API Gateway) на порту 8000
- Паттерн Strangler Fig for постепенной миграции от монолита к микросервисам
- Интеграция: синхронная (HTTP/REST) и асинхронная (Kafka)

## Задание 2: Реализация Proxy и Events сервисов ✅

### 2.1 Proxy Service (API Gateway)
**Файлы:**
- `src/microservices/proxy/main.go` - Основной код сервиса
- `src/microservices/proxy/go.mod` - Go модуль
- `src/microservices/proxy/Dockerfile` - Docker образ

**Функционал:**
- Маршрутизация запросов между монолитом и микросервисами
- Постепенная миграция через feature flags:
  - `GRADUAL_MIGRATION`: включение/выключение миграции
  - `MOVIES_MIGRATION_PERCENT`: процент трафика на микросервис (0-100%)
- Health check endpoint

### 2.2 Events Service (Kafka)
**Файлы:**
- `src/microservices/events/main.go` - Основной код сервиса
- `src/microservices/events/go.mod` - Go модуль с kafka-go зависимостью
- `src/microservices/events/go.sum` - Суммы проверок зависимостей
- `src/microservices/events/Dockerfile` - Docker образ

**Функционал:**
- Публикация событий в Kafka топики (movie-events, user-events, payment-events)
- Потребление событий из Kafka
- REST API для публикации событий
- Health check endpoint

## Задание 3: CI/CD и Kubernetes ✅

### 3.1 CI/CD Pipeline
**Обновленный файл:**
- `.github/workflows/docker-build-push.yml` - Добавлены сборки для events-service и proxy-service

**Функционал:**
- Автоматическая сборка всех 4 сервисов (monolith, movies-service, events-service, proxy-service)
- Push Docker образов в GHCR
- Кэширование через GitHub Actions

### 3.2 Kubernetes конфигурация
**Созданные файлы:**
- `src/kubernetes/events-service.yaml` - Deployment и Service для events-service
- `src/kubernetes/proxy-service.yaml` - Deployment и Service for proxy-service
- `src/kubernetes/ingress.yaml` - Обновлен для маршрутизации через proxy-service
- `src/kubernetes/circuit-breaker-config.yaml` - Istio circuit breaker конфигурация

## Задание 4: Helm Charts ✅

**Обновленные файлы:**
- `src/kubernetes/helm/templates/services/proxy-service.yaml` - Полный шаблон для proxy-service
- `src/kubernetes/helm/templates/services/events-service.yaml` - Полный шаблон for events-service
- `src/kubernetes/helm/values.yaml` - Уже содержит конфигурацию для всех сервисов

## Задание 5: Istio Circuit Breaker ✅

**Созданный файл:**
- `src/kubernetes/circuit-breaker-config.yaml` - DestinationRule для monolith и movies-service

**Конфигурация:**
- Connection pool limits (max connections, pending requests, requests per connection)
- Outlier detection (consecutive 5xx errors, ejection time, max ejection percent)

## Структура проекта

```
CinemaAbyss/
├── docs/
│   └── architecture/
│       ├── to-be-architecture.md    # To-Be архитектура
│       └── container-diagram.puml   # C4 диаграмма
├── src/
│   ├── monolith/                    # Монолит (существующий)
│   ├── microservices/
│   │   ├── movies/                  # Movies Service (существующий)
│   │   ├── proxy/                   # Proxy Service (новый)
│   │   └── events/                  # Events Service (новый)
│   └── kubernetes/
│       ├── events-service.yaml      # K8s Events Service
│       ├── proxy-service.yaml       # K8s Proxy Service
│       ├── ingress.yaml             # K8s Ingress
│       ├── circuit-breaker-config.yaml # Istio Circuit Breaker
│       └── helm/                    # Helm Charts
└── .github/workflows/
    └── docker-build-push.yml        # CI/CD Pipeline
```

## Технологии

- **Язык**: Go 1.23
- **Message Broker**: Kafka 2.13-2.7.0
- **База данных**: PostgreSQL 14
- **Оркестрация**: Kubernetes v1.19+
- **Package Management**: Helm v3.2.0+
- **Service Mesh**: Istio (для circuit breaker)
- **CI/CD**: GitHub Actions
- **Registry**: GHCR (GitHub Container Registry)

## Запуск локально

```bash
# Запуск всех сервисов
docker-compose up -d

# Проверка Proxy Service
curl http://localhost:8000/health
curl http://localhost:8000/api/movies

# Проверка Events Service
curl http://localhost:8000/api/events/publish -X POST -d '{"topic":"movie-events","type":"movie.viewed","payload":{"movie_id":1}}'

# Kafka UI
open http://localhost:8090
```

## Тестирование

```bash
# Запуск Postman тестов
cd tests/postman
npm install
npm run test:local
```
