FROM node:22-alpine
WORKDIR /app
COPY package.json ./package.json
RUN npm install --omit=dev
COPY server-monitor.mjs ./server-monitor.mjs
USER node
CMD ["node", "/app/server-monitor.mjs"]
