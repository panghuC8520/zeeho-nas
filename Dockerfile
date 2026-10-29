FROM node:20-alpine

ENV NODE_ENV=production \
    TZ=Asia/Shanghai \
    PORT=8080 \
    CRON_ENABLE=1 \
    CRON_TIME=07:05

WORKDIR /app

COPY package.json ./
COPY server.js ./
COPY script ./script

RUN mkdir -p /app/data

VOLUME ["/app/data"]
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["node", "server.js"]
