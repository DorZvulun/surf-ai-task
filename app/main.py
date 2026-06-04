import os
from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/")
def index():
    return jsonify(
        pod_name=os.environ.get("POD_NAME", "unknown"),
        pod_ip=os.environ.get("POD_IP", "unknown"),
        app="ironman-web-app",
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
# comment to test push Actions trigger 2