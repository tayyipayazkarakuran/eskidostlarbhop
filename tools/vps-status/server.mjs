import { createServer } from "node:http";
import { queryGoldSrcServer } from "./a2s.js";

const host = process.env.GAME_HOST || "45.143.11.212";
const port = Number(process.env.GAME_PORT || 27015);
const httpHost = process.env.HTTP_HOST || "0.0.0.0";
const httpPort = Number(process.env.HTTP_PORT || 3001);
const allowedOrigin = process.env.CORS_ORIGIN || "*";

const server = createServer(async (request, response) => {
  const url = new URL(request.url || "/", `http://${request.headers.host || "localhost"}`);
  response.setHeader("access-control-allow-origin", allowedOrigin);
  response.setHeader("access-control-allow-methods", "GET, OPTIONS");
  response.setHeader("access-control-allow-headers", "accept");

  if (request.method === "OPTIONS") {
    response.writeHead(204);
    response.end();
    return;
  }

  if (request.method !== "GET" || url.pathname !== "/status") {
    response.writeHead(404, { "content-type": "application/json; charset=utf-8" });
    response.end(JSON.stringify({ ok: false, error: "Not found" }));
    return;
  }

  try {
    const payload = await queryGoldSrcServer({ host, port });
    response.writeHead(200, {
      "cache-control": "no-store",
      "content-type": "application/json; charset=utf-8",
      "x-content-type-options": "nosniff",
    });
    response.end(JSON.stringify({ ok: true, ...payload }));
  } catch (error) {
    response.writeHead(200, {
      "cache-control": "no-store",
      "content-type": "application/json; charset=utf-8",
      "x-content-type-options": "nosniff",
    });
    response.end(JSON.stringify({
      ok: true,
      online: false,
      server: { address: `${host}:${port}` },
      players: [],
      error: String(error.message || error),
      fetchedAt: Math.floor(Date.now() / 1000),
    }));
  }
});

server.listen(httpPort, httpHost, () => {
  console.log(`ESKIDOSTLAR status helper listening on http://${httpHost}:${httpPort}/status`);
});
