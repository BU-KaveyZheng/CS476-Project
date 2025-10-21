from flask import Flask, jsonify
import numpy as np
import time

app = Flask(__name__)

@app.route("/multiply")
def multiply(): 
    a = np.random.rand(2000, 2000)
    b = np.random.rand(2000, 2000)
    
    start = time.time()
    
    np.dot(a, b)

    end = time.time()
    total_time = end - start

    return jsonify( {
        "runtime": total_time,
        "size": "2000, 2000"
    } )

@app.route("/hello")
def hello():
    return jsonify( {
        "message": "hello world"
    })

@app.route("/")
def default():
    return jsonify({
        "message": "This is the default page."
    })

if __name__ == "__main__":
    app.run(host = "0.0.0.0", port = 3000)
