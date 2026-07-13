FROM golang:1.23-alpine3.20 AS builder


WORKDIR /app

COPY go.mod ./
COPY go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o /app/events .

FROM alpine:3.20

WORKDIR /app

COPY --from=builder /app/events .

EXPOSE 8082

CMD ["./events"]
