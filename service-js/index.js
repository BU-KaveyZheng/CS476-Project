import express from "express";

const app = express();
const port = process.env.PORT || 3000;

app.get("/", (req, res) => {
  res.json({
    message: "Hello from /!"
  });
});

app.get("/service-js", (req, res) => {
  res.json({
    message: "Hello from /service-js!"
  });
});

app.listen(port, () => {
  console.log(`Service running on port ${port}`);
});
