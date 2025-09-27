import express from "express";
import { createProxyMiddleware } from "http-proxy-middleware";

const app = express();
const port = process.env.PORT || 8080;

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
    pathRewrite: { '^/proxy': '' } // remove /proxy from path
  })(req, res, next);
});

app.listen(port, () => {
  console.log(`Dispatcher listening on port ${port}`);
});
