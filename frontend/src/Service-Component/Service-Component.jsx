import { useState } from "react";
import "./style.css";

function ServiceComponent({ name, functions, dispatcherUrl }) {
  const [responses, setResponses] = useState({});
  const [criticalFlags, setCriticalFlags] = useState({});

  const handleClick = async (fn) => {
    const critical = criticalFlags[fn] || false;
    const proxyUrl = `${dispatcherUrl}/proxy${fn}?service=${name}&critical=${critical}`;
    const start = performance.now();

    try {
      const res = await fetch(proxyUrl);
      const end = performance.now();
      
      // Check if response is JSON
      const contentType = res.headers.get("content-type");
      let data;
      
      if (contentType && contentType.includes("application/json")) {
        data = await res.json();
      } else {
        // If not JSON, get as text
        const text = await res.text();
        data = {
          status: res.status,
          statusText: res.statusText,
          body: text
        };
      }
      
      setResponses((prev) => ({
        ...prev, [fn]: {
          message: data, proxyUrl, timeMS: (end - start).toFixed(2)
        },
      }));
    } catch (err) {
      const end = performance.now();
      setResponses((prev) => ({
        ...prev, [fn]: {
          message: { error: "Error: " + err.message }, proxyUrl, timeMS: (end - start).toFixed(2)
        },
      }));
    }
  };

  const toggleCritical = (fn) => {
    setCriticalFlags((prev) => ({
      ...prev,
      [fn]: !prev[fn]
    }));
  };

  return (
    <div className="service-box">
      <h1 className="service-name">{name}</h1>
      <div className="function-list">
        {functions.map((fn, i) => (
          <div key={i} className="function-item">
            <div className="buttons">
              <button className="function-btn" onClick={() => handleClick(fn)}>
                {fn}
              </button>
              <label className="checkbox">
                Critical
                <input
                  type="checkbox"
                  checked={!!criticalFlags[fn]}
                  onChange={() => toggleCritical(fn)}
                />
              </label>
            </div>

            {responses[fn] && (
              <div className="response-box">
                <pre><strong>Dispatcher URL:</strong> {responses[fn].proxyUrl}</pre>
                <pre><strong>Time:</strong> {responses[fn].timeMS} ms</pre>
                <pre>{JSON.stringify(responses[fn].message, null, 2)}</pre>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}

export default ServiceComponent;
