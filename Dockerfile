# Build stage
FROM golang:1.24-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /sal ./cmd/api

# Run stage
FROM alpine:3.21

RUN apk --no-cache add ca-certificates

COPY --from=builder /sal /sal

EXPOSE 8000

CMD ["/sal"]