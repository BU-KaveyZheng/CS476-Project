FROM golang:1.23-alpine AS builder

WORKDIR /build

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY main.go .

# Build
RUN CGO_ENABLED=0 GOOS=linux go build -o custom-scheduler main.go

# Final stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /root/

COPY --from=builder /build/custom-scheduler .

# Create cache directory
RUN mkdir -p /cache

ENV CACHE_FILE=/cache/carbon_cache.json
ENV CARBON_AWARE_MODE=true

CMD ["./custom-scheduler"]

