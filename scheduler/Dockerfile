FROM golang:1.25-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY main.go .

# Build the scheduler
RUN CGO_ENABLED=0 GOOS=linux go build -o custom-scheduler main.go

# Final stage
FROM alpine:latest

WORKDIR /root/

# Copy the binary from builder
COPY --from=builder /app/custom-scheduler .

# Run the scheduler
CMD ["./custom-scheduler"]

