FROM golang:1.25-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
COPY main.go .
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/main .

EXPOSE 3000 2112
CMD ["./main"]
