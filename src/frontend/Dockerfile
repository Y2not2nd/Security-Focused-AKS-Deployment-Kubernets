# Stage 1: Build Angular app
FROM node:18-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci               # Install dependencies (clean install)
COPY . .
RUN npm run build --prod

# Stage 2: Serve with Nginx
FROM nginx:alpine
COPY --from=builder /app/dist/frontend /usr/share/nginx/html
# Copy custom Nginx config for SPA routing
COPY nginx.conf /etc/nginx/conf.d/default.conf 