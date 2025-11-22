from flask import Flask, request, jsonify
import numpy as np
import time

app = Flask(__name__)

busy = False

@app.route("/multiply")
def multiply(): 
    global busy
    if busy: return jsonify({ "error": "service busy" })
    busy = True

    size = request.args.get("size", default=2000, type=int)
    a = np.random.rand(size, size)
    b = np.random.rand(size, size)
    
    start = time.time()
    np.dot(a, b)
    end = time.time()
    total_time = end - start

    busy = False
    return jsonify({ "size": f"{size},{size}" })

@app.route("/status")
def status():
    return jsonify({ "busy": busy })

@app.route("/")
def default():
    return jsonify({ "message": "This is the default page." })

if __name__ == "__main__":
    app.run(host = "0.0.0.0", port = 3000)
