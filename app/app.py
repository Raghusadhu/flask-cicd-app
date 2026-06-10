from flask import Flask, jsonify
import os

app = Flask(__name__)

ENV = os.environ.get("APP_ENV", "development")

@app.route("/")
def home():
    return jsonify({
        "message": "Flask CI/CD Demo App",
        "environment": ENV,
        "version": "1.0.0"
    })

@app.route("/health")
def health():
    return jsonify({"status": "healthy", "env": ENV}), 200

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
