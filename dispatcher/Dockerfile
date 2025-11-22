FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
# Copy source files but exclude .env (use environment variables or secrets in Kubernetes)
COPY index.js carbonCache.js ./
EXPOSE 8080
CMD ["node", "index.js"]
