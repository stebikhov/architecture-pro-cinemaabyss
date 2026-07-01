# Локальное развертывание с Kind

Этот документ описывает процесс локального развертывания CinemaAbyss с использованием Kind (Kubernetes in Docker).

## Быстрый старт

### 1. Запустите скрипт развертывания

```powershell
# Из корня проекта
.\deploy-kind.ps1
```

Скрипт:
- Создает Kind кластер
- Собирает Docker образы
- Загружает образы в Kind
- Разворачивает все сервисы в Kubernetes
- Настраивает Ingress

### 2. Настройте доступ

Добавьте запись в `C:\Windows\System32\drivers\etc\hosts` (требуются права администратора):

```
127.0.0.1 cinemaabyss.example.com
```

### 3. Запустите port-forward

В отдельном терминале:

```powershell
kubectl port-forward -n ingress-nginx service/ingress-nginx-controller 8080:80
```

### 4. Тестируйте

```powershell
# Через API Gateway
curl http://localhost:8080/api/movies
curl http://localhost:8080/api/users
curl http://localhost:8080/health

# Через домен (после добавления в hosts)
curl http://cinemaabyss.example.com/api/movies
```

## Дополнительные команды

### Проверка статуса

```powershell
# Проверить поды
kubectl get pods -n cinemaabyss

# Проверить сервисы
kubectl get svc -n cinemaabyss

# Проверить логи
kubectl logs -n cinemaabyss deployment/proxy-service
kubectl logs -n cinemaabyss deployment/events-service
```

### Пересоздание кластера

```powershell
# Полная очистка и пересоздание
.\deploy-kind.ps1 -Clean

# Только очистка
.\cleanup-kind.ps1
```

### Тестирование

```powershell
# Запустить Postman тесты
cd tests/postman
npm install
npm run test:local
```

## Troubleshooting

### Kind не найден
```powershell
# Установить Kind вручную
curl.exe -Lo kind.exe https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64
New-Item -ItemType Directory -Force -Path .\bin
Move-Item .\kind.exe .\bin\kind.exe -Force
```

### Ошибка "connection refused"
Убедитесь, что Docker запущен и работает.

### Поды не запускаются
Проверьте логи:
```powershell
kubectl describe pod <pod-name> -n cinemaabyss
kubectl logs <pod-name> -n cinemaabyss
```

### Ingress не работает
Проверьте статус ingress контроллера:
```powershell
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

## Удаление

```powershell
# Удалить кластер
.\cleanup-kind.ps1

# Или вручную
kind delete cluster --name cinemaabyss
```

## Ресурсы кластера

- **CPU**: минимум 2 ядра
- **RAM**: минимум 4GB (рекомендуется 8GB)
- **Диск**: минимум 10GB свободного места

## Альтернативы

Если Kind не работает, можно использовать:
- Minikube (`minikube start`)
- Docker Desktop Kubernetes
- Удаленный Kubernetes кластер
