const express = require("express");
const app = express();
const PORT = process.env.PORT || 3000;

app.get("/", (req, res) => {
  res.json({
    status: "success",
    architecture: "Azure Container Apps (PaaS)",
    message:
      "🚀 Hello from Express running on Azure Container Apps via GitHub Actions!",
    timestamp: new Date(),
  });
});

app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
