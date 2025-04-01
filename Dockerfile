FROM docker.io/library/golang:1.22 as builder
WORKDIR /app
COPY . .
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -o main .

FROM docker.io/library/alpine:latest
WORKDIR /root/
COPY --from=builder /app/main .
COPY frontend/ frontend/
EXPOSE 8080
CMD ["./main"] 