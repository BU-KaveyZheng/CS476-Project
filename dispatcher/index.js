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
app.use(cors({
  origin: '*',
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
})); 

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
  
  // strip the /proxy path
  req.url = req.url.replace(/^\/proxy/, "") 

  return createProxyMiddleware({
    target,
    changeOrigin: true,
    pathRewrite: { '^/proxy': '' },
    onProxyReq: function(proxyReq, req, res) {
      console.log(`Proxying ${req.method} ${req.url} to ${target}`);
    },
    onProxyRes: function(proxyRes, req, res) {
      proxyRes.headers['access-control-allow-origin'] = '*';
      proxyRes.headers['access-control-allow-credentials'] = 'true';
      proxyRes.headers['access-control-allow-methods'] = 'GET, POST, PUT, DELETE, OPTIONS';
      proxyRes.headers['access-control-allow-headers'] = 'Content-Type, Authorization';
    },
    onError: function(err, req, res) {
      console.error('Proxy error:', err);
      res.status(500).json({ error: 'Proxy error', message: err.message });
    }
  })(req, res, next);
});

app.listen(port, () => {
  console.log(`Dispatcher listening on port ${port}`);
});
