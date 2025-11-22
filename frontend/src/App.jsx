import { useState } from "react";
import ServiceComponent from "./Service-Component/Service-Component";
import "./App.css";

function App() {
  const [dispatcherUrl, setDispatcherUrl] = useState("");

  return (
    <div className="app-container">
      <header className="app-header">
        <h1>🚀 Microservices Dashboard</h1>
        <div className="url-div">
          <label htmlFor="dispatcher-url">Dispatcher URL:</label>
          <input
            id="dispatcher-url"
            type="text"
            value={dispatcherUrl}
            onChange={(e) => setDispatcherUrl(e.target.value)}
            placeholder="..."
          />
        </div>
      </header>

      <ServiceComponent
        name="my-node-service"
        functions={["/", "/service-js"]}
        dispatcherUrl={dispatcherUrl}
      />
      <ServiceComponent
        name="matrix-mult-service"
        functions={["/", "/multiply", "/status"]}
        dispatcherUrl={dispatcherUrl}
      />
    </div>
  );
}

export default App;