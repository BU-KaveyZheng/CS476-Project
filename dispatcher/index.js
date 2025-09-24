import express from "express";
import { createProxyMiddleware } from "http-proxy-middleware";

const app = express();
const port = process.env.PORT || 8080;

/**
 * Decide which backend to route to.
 * Example:  /service-js/*   -> my-node-service:3000
 *           /foo-prod/*     -> my-foo-prod:3000
 */
function targetForPath(path) {
  if (path.startsWith("/service-js")) return "http://my-node-service:3000";
  if (path.startsWith("/foo-prod"))   return "http://my-foo-prod:3000";
  // default/fallback:
  return null;
}

app.use((req, res, next) => {
  const target = targetForPath(req.path);
  if (!target) return res.status(404).send("No matching backend");
  return createProxyMiddleware({ target, changeOrigin: true })(req, res, next);
});

app.listen(port, () => {
  console.log(`Dispatcher listening on port ${port}`);
});
