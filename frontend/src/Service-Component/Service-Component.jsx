import { useState } from "react";
import "./style.css";

function ServiceComponent({ name, functions, dispatcherUrl }) {
  const [responses, setResponses] = useState({});

  const handleClick = async (fn) => {
    try {
      const res = await fetch(
        `${dispatcherUrl}/proxy${fn}?service=${name}`,
        { method: "GET" }
      );
      const data = await res.json();
      setResponses((prev) => ({ ...prev, [fn]: data, }));
    } catch (err) {
      setResponses((prev) => ({ ...prev, [fn]: "Error: " + err.message, }));
    }
  };

  return (
    <div className="service-box">
      <h1 className="service-name">{name}</h1>
      <div className="function-list">
        {functions.map((fn, i) => (
          <div key={i} className="function-item">
            <button
              className="function-btn"
              onClick={() => handleClick(fn)}
            >
              {fn}
            </button>

            {responses[fn] && (
              <div className="response-box">
                <strong>Response for {fn}:</strong>
                <pre>{JSON.stringify(responses[fn], null, 2)}</pre>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}

export default ServiceComponent;
