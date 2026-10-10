FROM node:20-bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       python3 python3-pip ffmpeg ca-certificates \
    && pip3 install --break-system-packages -U yt-dlp \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY backend/package*.json ./
RUN npm install --omit=dev

COPY backend/ ./

ENV NODE_ENV=production
ENV PATH="/usr/local/bin:/usr/bin:/bin"

EXPOSE 3000

CMD ["node", "server.js"]
