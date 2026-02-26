FROM denoland/deno:2.0.0
WORKDIR /app
COPY deno.json .
RUN deno install
COPY src/ src/
EXPOSE 3800
CMD ["deno", "run", "--allow-net", "--allow-env", "--allow-read", "src/server.ts"]
