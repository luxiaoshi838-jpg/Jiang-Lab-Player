FROM node:24-bookworm-slim

RUN apt-get update -qq && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /srv/upstream
RUN git clone --filter=blob:none https://github.com/huangxd-/danmu_api.git . \
    && git checkout f47b786876f2ab51ef69518e5e0b1c0574664589 \
    && npm install --omit=dev --ignore-scripts --no-audit --no-fund
WORKDIR /srv/suibo
COPY services/danmaku/gateway.mjs /srv/suibo/gateway.mjs
ENV NODE_ENV=production
EXPOSE 10000
CMD ["node", "/srv/suibo/gateway.mjs"]
