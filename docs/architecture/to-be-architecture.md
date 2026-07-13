# To-Be Архитектура системы "Кинобездна"

## 1. Обзор архитектуры

To-Be архитектура представляет собой микросервисную систему, построенную на принципах domain-driven design (DDD) с использованием паттерна Strangler Fig for постепенного перехода from монолита к микросервисам.

## 2. Домены системы

### 2.1. Domain: Users (Пользователи)
- **Ответственность**: Аутентификация, управление профилями, избранное
- **Микросервис**: `users-service` (порт 8083)
- **Таблицы БД**: `users`, `user_ratings`, `favorites`
- **События Kafka**: `user-events` (регистрация, вход, оценка)

### 2.2. Domain: Movies (Фильмы/Метаданные)
- **Ответственность**: Каталог фильмов, жанры, рейтинги, метаданные
- **Микросервис**: `movies-service` (порт 8081) ✅ Уже выделен
- **Таблицы БД**: `movies`, `movie_genres`, `ratings`
- **События Kafka**: `movie-events` (просмотр, оценка, добавление)

### 2.3. Domain: Payments (Платежи)
- **Ответственность**: Обработка платежей, транзакции, возвраты
- **Микросервис**: `payments-service` (порт 8084)
- **Таблицы БД**: `payments`
- **События Kafka**: `payment-events` (успешные/неуспешные платежи)

### 2.4. Domain: Subscriptions (Подписки)
- **Ответственность**: Управление подписками, тарифные планы, скидки
- **Микросервис**: `subscriptions-service` (порт 8085)
- **Таблицы БД**: `subscriptions`, `discounts`
- **События Kafka**: `subscription-events`

### 2.5. Domain: Events (События/Инфраструктура)
- **Ответственность**: Асинхронная коммуникация между сервисами
- **Микросервис**: `events-service` (порт 8082)
- **Инфраструктура**: Kafka брокер, ZooKeeper

### 2.6. Domain: API Gateway (Шлюз)
- **Ответственность**: Единая точка входа, маршрутизация, постепенная миграция
- **Микросервис**: `proxy-service` (порт 8000)
- **Функции**: Strangler Fig pattern, feature flags, процентная маршрутизация

## 3. Интеграционное взаимодействие

### 3.1. Синхронное взаимодействие (HTTP/REST)
```
Клиент → Proxy Service (:8000) → [Микросервисы | Монолит]
```

**Маршруты:**
- `/api/movies/**` → movies-service (или monolith при gradual migration)
- `/api/users/**` → users-service (или monolith)
- `/api/payments/**` → payments-service (или monolith)
- `/api/subscriptions/**` → subscriptions-service (или monolith)
- `/api/events/**` → events-service

### 3.2. Асинхронное взаимодействие (Kafka)
```
Микросервис → Kafka (:9092) → Topics → Events Service → Логирование/Обработка
```

**Топики:**
- `movie-events` (1 партиция, RF=1)
- `user-events` (1 партиция, RF=1)
- `payment-events` (1 партиция, RF=1)

### 3.3. База данных
**Подход**: Shared Database (на этапе миграции)
- PostgreSQL 14 на порту 5432
- Общие таблицы для монолита и микросервисов
- Постепенное разделение на сервисные БД

## 4. Единая точка вызова сервисов

### 4.1. API Gateway (Proxy Service)
**Функции:**
- Маршрутизация запросов между монолитом и микросервисами
- Постепенная миграция через feature flags:
  - `GRADUAL_MIGRATION`: включение/выключение миграции
  - `MOVIES_MIGRATION_PERCENT`: процент трафика на микросервис (0-100%)
- Фасад для всех внешних клиентов

**Конфигурация:**
```yaml
PORT: 8000
MONOLITH_URL: http://monolith:8080
MOVIES_SERVICE_URL: http://movies-service:8081
EVENTS_SERVICE_URL: http://events-service:8082
GRADUAL_MIGRATION: "true"
MOVIES_MIGRATION_PERCENT: "50"
```

## 5. Инфраструктура

### 5.1. Оркестрация (Kubernetes)
- **Cluster**: v1.19+
- **Namespace**: `cinemaabyss`
- **Deployment**: Deployment + Service для каждого сервиса
- **StatefulSet**: PostgreSQL, Kafka, ZooKeeper
- **Ingress**: NGINX controller

### 5.2. Управление деплоем (Helm)
- **Chart**: `src/kubernetes/helm/`
- **Values**: Конфигурация всех сервисов
- **Templates**: Шаблоны для Deployment, Service, Ingress

### 5.3. CI/CD (GitHub Actions)
- **Workflow**: `.github/workflows/docker-build-push.yml`
- **Registry**: GHCR (`ghcr.io/db-exp/cinemaabysstest/`)
- **Этапы**:
  1. Сборка Docker-образов
  2. Тестирование (API tests)
  3. Push в GHCR
  4. Деплой в Kubernetes (Helm)

## 6. Паттерн Strangler Fig

### 6.1. Механизм работы
1. Proxy Service получает запрос
2. Проверяет feature flag `GRADUAL_MIGRATION`
3. Если включен:
   - Генерирует случайное число 0-100
   - Если число ≤ `MOVIES_MIGRATION_PERCENT` → маршрутизирует в микросервис
   - Иначе → маршрутизирует в монолит
4. Если выключен → всегда маршрутизирует в микросервис

### 6.2. Преимущества
- **Без простоя**: Пользователи не замечают перехода
- **Контролируемый**: Можно регулировать процент трафика
-.Reverseable: Можно откатить в любой момент
- **Тестируемый**: Можно тестировать на части трафика

## 7. Технологический стек

| Компонент | Технология | Версия |
|-----------|------------|--------|
| Микросервисы | Go | 1.23 |
| Монолит | Go | 1.23 |
| База данных | PostgreSQL | 14 |
| Message Broker | Kafka | 2.13-2.7.0 |
| Coordination | ZooKeeper | latest |
| Оркестрация | Kubernetes | v1.19+ |
| Package Mgmt | Helm | v3.2.0+ |
| CI/CD | GitHub Actions | - |
| Registry | GHCR | - |
| Kafka Monitoring | Kafka UI | latest |

## 8. Диаграмма контейнеров (C4 Level 2)

См. файл: [container-diagram.puml](container-diagram.puml)

Для визуализации используйте:
- PlantUML Server: https://www.plantuml.com/plantuml/
- IntelliJ IDEA с плагином PlantUML
- VS Code с расширением PlantUML

## 9. План миграции

### Этап 1: ✅ Завершён
- Выделен микросервис Movies
- Настроена инфраструктура (K8s, Kafka, Helm)
- Реализован CI/CD pipeline

### Этап 2: В процессе
- Реализация Proxy Service (API Gateway)
- Реализация Events Service
- Постепенная маршрутизация трафика

### Этап 3: Планируется
- Выделение Users Service
- Выделение Payments Service
- Выделение Subscriptions Service
- Разделение базы данных

### Этап 4: Завершение
- Полный переход на микросервисы
- Отключение монолита
- Оптимизация производительности
