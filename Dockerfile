# syntax=docker/dockerfile:1.7
ARG NODE_IMAGE=node:20-bookworm-slim

# المرحلة 1: البناء (تثبيت التبعيات وبناء التطبيق)
FROM ${NODE_IMAGE} AS build
WORKDIR /app
# تثبيت الأدوات اللازمة لبناء better-sqlite3
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ && rm -rf /var/lib/apt/lists/*
COPY package.json package-lock.json ./
COPY shared/package.json ./shared/
COPY server/package.json ./server/
COPY client/package.json ./client/
RUN npm ci
COPY . .
RUN npm run build && npm prune --omit=dev

# المرحلة 2: التشغيل (نسخ الناتج فقط)
FROM ${NODE_IMAGE} AS runtime
WORKDIR /app
# تثبيت python3 و ca-certificates (مطلوبان للتشغيل)
RUN apt-get update && apt-get install -y --no-install-recommends python3 ca-certificates && rm -rf /var/lib/apt/lists/*
ENV NODE_ENV=production
ENV PORT=7860
ENV CATALOG_SYNC_DISABLED=1
COPY --from=build --chown=node:node /app/package.json /app/package-lock.json ./
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/shared ./shared
COPY --from=build --chown=node:node /app/server/package.json ./server/package.json
COPY --from=build --chown=node:node /app/server/dist ./server/dist
COPY --from=build --chown=node:node /app/server/catalog-updater ./server/catalog-updater
COPY --from=build --chown=node:node /app/seed_production_keys.js ./seed_production_keys.js
COPY --from=build --chown=node:node /app/client/dist ./client/dist
RUN mkdir -p /app/server/data && chown -R node:node /app/server/data
USER node
EXPOSE 7860
VOLUME ["/app/server/data"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 CMD node -e "fetch('http://127.0.0.1:' + (process.env.PORT || 7860) + '/api/ping').then((res) => { if (!res.ok) process.exit(1); }).catch(() => process.exit(1));"
CMD ["sh", "-c", "node seed_production_keys.js && node server/dist/index.js"]
