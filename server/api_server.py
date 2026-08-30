from flask import Flask, jsonify, send_from_directory
import os
import json

app = Flask(__name__)
CACHE_FILE = "matches.json"

@app.route('/matches', methods=['GET'])
def get_matches():
    if not os.path.exists(CACHE_FILE):
        return jsonify({"error": "Cache not initialized"}), 503
    
    try:
        with open(CACHE_FILE, 'r') as f:
            data = json.load(f)
        return jsonify(data)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy"})

if __name__ == "__main__":
    # Port 8080 as requested
    app.run(host="0.0.0.0", port=8080)
