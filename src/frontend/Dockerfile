# Stage 1: Build Angular app
FROM node:18-alpine AS builder
WORKDIR /app

# Copy package files first to leverage Docker cache
COPY package.json ./

# Install dependencies
RUN npm install

# Copy the rest of the application
COPY . .

# Build the application
RUN npm run build

# Stage 2: Serve with Nginx
FROM nginx:alpine
COPY --from=builder /app/dist/frontend /usr/share/nginx/html
# Copy custom Nginx config for SPA routing
COPY nginx.conf /etc/nginx/conf.d/default.conf 