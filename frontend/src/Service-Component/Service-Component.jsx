import { useState } from "react";
import "./style.css";

function ServiceComponent({ name, functions, dispatcherUrl }) {
  const [responses, setResponses] = useState({});

  const handleClick = async (fn) => {
    const proxyUrl = `${dispatcherUrl}/proxy${fn}?service=${name}`;
    try {
      const res = await fetch(proxyUrl);
      const data = await res.json();
      setResponses((prev) => ({ ...prev, [fn]: { message: data, proxyUrl }, }));
    } catch (err) {
      setResponses((prev) => ({ ...prev, [fn]: { message: "Error: " + err.message, proxyUrl }, }));
    }
  };

  return (
    <div className="service-box">
      <h1 className="service-name">{name}</h1>
      <div className="function-list">
        {functions.map((fn, i) => (
          <div key={i} className="function-item">
            <button className="function-btn" onClick={() => handleClick(fn)}>
              {fn}
            </button>

            {responses[fn] && (
              <div className="response-box">
                <pre><strong>Dispatcher URL:</strong> {responses[fn].proxyUrl}</pre>
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
