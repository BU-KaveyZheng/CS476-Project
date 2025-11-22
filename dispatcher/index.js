import express from "express";
import cors from "cors";
import { createProxyMiddleware } from "http-proxy-middleware";

const app = express();
const port = process.env.PORT || 8080;

// Enable CORS for specific routes
// app.use(cors({
//   origin: 'http://localhost:3000',
//   credentials: true
// })); 

// ONLY FOR DEVELOPMENT - allows all routes
app.use(cors()); 

function targetForRequest(req) {
  const service = req.query.service;
  if (!service) return null;

  // construct URL dynamically
  const port = 3000;
  return `http://${service}:${port}`;
};

// Middleware
app.use("/proxy", (req, res, next) => {
  const target = targetForRequest(req);
  if (!target) return res.status(404).send("No matching backend");
  
  return createProxyMiddleware({
    target,
    changeOrigin: true,
    pathRewrite: { '^/proxy': '' },
    onProxyRes: function(proxyRes, req, res) {
      proxyRes.headers['access-control-allow-origin'] = '*';
      proxyRes.headers['access-control-allow-credentials'] = 'true';
    }
  })(req, res, next);
});

app.listen(port, () => {
  console.log(`Dispatcher listening on port ${port}`);
});
