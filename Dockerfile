FROM node:26-alpine
# The application uses only Node.js built-ins. Patch OS packages and remove unused package managers.
RUN apk upgrade --no-cache \
    && rm -rf /usr/local/lib/node_modules /opt/yarn* \
       /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/yarn /usr/local/bin/yarnpkg
ENV NODE_ENV=production PORT=8080
WORKDIR /app
COPY --chown=node:node app/package.json ./package.json
COPY --chown=node:node app/src ./src
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "src/server.js"]
