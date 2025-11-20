import { useState } from "react";
import "./style.css";

function ServiceComponent({ name, functions, dispatcherUrl }) {
  const [responses, setResponses] = useState({});

  const handleClick = async (fn) => {
    if (!dispatcherUrl) {
      setResponses((prev) => ({ ...prev, [fn]: "Error: Please enter a Dispatcher URL first" }));
      return;
    }

    try {
      const url = `${dispatcherUrl}/proxy${fn}?service=${name}`;
      console.log('Fetching:', url); // Debug log
      
      const res = await fetch(url, { 
        method: "GET",
        headers: {
          'Accept': 'application/json',
        },
        mode: 'cors', // Explicitly enable CORS
      });
      
      console.log('Response status:', res.status); // Debug log
      
      if (!res.ok) {
        const errorText = await res.text();
        setResponses((prev) => ({ 
          ...prev, 
          [fn]: `Error: HTTP ${res.status} - ${errorText || res.statusText}` 
        }));
        return;
      }
      
      const contentType = res.headers.get('content-type');
      let data;
      
      if (contentType && contentType.includes('application/json')) {
        data = await res.json();
      } else {
        const text = await res.text();
        data = { message: text };
      }
      
      setResponses((prev) => ({ ...prev, [fn]: data, }));
    } catch (err) {
      console.error('Fetch error:', err); // Debug log
      setResponses((prev) => ({ 
        ...prev, 
        [fn]: `Error: ${err.message}. This might be a CORS issue. Check browser console for details.` 
      }));
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
