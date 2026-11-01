FROM node:24-alpine
WORKDIR /app
COPY package.json ./
COPY src ./src
ENV HOST=0.0.0.0
EXPOSE 3003
CMD ["node", "src/index.js"]
