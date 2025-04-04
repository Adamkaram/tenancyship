FROM docker.io/library/golang:1.22-alpine as builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o main .

FROM docker.io/library/alpine:3.19
WORKDIR /app

# Install necessary packages
RUN apk add --no-cache ca-certificates curl

# Create and use non-root user
RUN adduser -D -H -h /app appuser
RUN chown -R appuser:appuser /app

# Copy the binary and frontend files
COPY --from=builder --chown=appuser:appuser /app/main .
COPY --chown=appuser:appuser frontend/ frontend/

# Switch to non-root user
USER appuser

# Set resource limits
ENV GOGC=100
ENV GOMAXPROCS=4

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -f http://localhost:8080/health || exit 1

# Run the application
CMD ["./main"] 