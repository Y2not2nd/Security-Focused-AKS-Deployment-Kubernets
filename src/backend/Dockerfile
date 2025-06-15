# Stage 1: Build the Go binary
FROM golang:1.19-alpine AS builder
WORKDIR /app
COPY go.mod ./
COPY go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o backend .

# Stage 2: Create a lightweight image for running
FROM gcr.io/distroless/base-debian11
COPY --from=builder /app/backend /backend
# Run as non-root user for security
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/backend"] 