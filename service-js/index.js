import express from "express";

const app = express();
const port = process.env.PORT || 3000;

app.get("/", (_req, res) => {
  res.send("Hello from Kubernetes!");
});

app.listen(port, () => {
  console.log(`Service running on port ${port}`);
});
