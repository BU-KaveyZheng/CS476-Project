# Build stage
FROM golang:1.25 AS builder

WORKDIR /app

# Copy everything
COPY . .

# Download dependencies and build
RUN go mod download && go mod tidy && CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o carbon-scheduler .

# Final stage
FROM alpine:latest

# Install ca-certificates for HTTPS requests
RUN apk --no-cache add ca-certificates

WORKDIR /root/

# Copy the binary from builder stage
COPY --from=builder /app/carbon-scheduler .

# Create a non-root user
RUN adduser -D -s /bin/sh scheduler
USER scheduler

# Expose port (if needed for health checks)
EXPOSE 8080

# Run the scheduler
CMD ["./carbon-scheduler"]
