from flask import Flask, jsonify
from flask_cors import CORS
import requests
import re
import time

app = Flask(__name__)
CORS(app)

# Simple in-memory cache
# Format: { "race_id": {"timestamp": 1234567, "data": [...]} }
cache = {}
CACHE_DURATION = 600  # seconds

def extract_riders_from_html(raw_data_list):
    # Parses the raw HTML data to extract rider information
    riders = []
    for entry in raw_data_list:
        # Skip invalid entries
        if len(entry) < 2: continue

        # Extract Name
        name_match = re.search(r"onClick='clrac\(\);'>(.*?)</a>", entry[0])
        name = name_match.group(1) if name_match else "Unknown"

        # Extract Miles (The improved multi-match regex)
        val_str = str(entry[1])
        mile_match = re.search(r"([\d\.]+)\s*(?:mi|miles|mile)", val_str, re.IGNORECASE)
        miles = float(mile_match.group(1)) if mile_match else (9999.0 if "FIN" in val_str else 0.0)

        # Extract Metadata
        meta_match = re.search(r"value='(.*?)'", entry[0])
        gender, category = "", ""
        if meta_match:
            parts = meta_match.group(1).split(',')
            # Index 4 is usually Gender, Index 7 is usually Category
            gender = parts[4].strip() if len(parts) > 4 else ""
            category = parts[7].strip() if len(parts) > 7 else ""

        riders.append({"n": name, "m": miles, "g": gender, "c": category})
    return riders

@app.route('/race/<race_id>')
def scrape_trackleaders(race_id):
    now = time.time()
    if race_id in cache and (now - cache[race_id]['timestamp'] < CACHE_DURATION):
        return jsonify(cache[race_id]['data'])

    # Clean the race_id just in case
    race_id = race_id.strip().lower()
    base_url = f"https://trackleaders.com/{race_id}"
    
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "application/json, text/javascript, */*; q=0.01",
        "Accept-Language": "en-US,en;q=0.9",
        "Referer": base_url, # This is crucial for bypassing 403s on JSON endpoints
        "X-Requested-With": "XMLHttpRequest"
    }

    try:
        session = requests.Session()
        
        # Fetch the sortlist.json endpoint
        response = session.get(f"{base_url}/sortlist.json", headers=headers, timeout=10)
        if response.status_code != 200:
            return jsonify({"error": f"TrackLeaders returned status {response.status_code}"}), response.status_code

        # Parse JSON response to populate riders if successful
        raw_data = response.json()
        riders = extract_riders_from_html(raw_data)
        riders.sort(key=lambda x: x['m'], reverse=True)

        # Cache the result
        cache[race_id] = {'timestamp': now, 'data': riders}

        return jsonify(riders)

    except Exception as e:
        return jsonify({"error": str(e)}), 500