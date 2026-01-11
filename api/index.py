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
    """Legacy parser for 'spots' array format found in f.php/spots.js"""
    riders = []
    for entry in raw_data_list:
        if len(entry) < 2: continue

        # 1. Extract Name
        name_match = re.search(r"onClick='clrac\(\);'>(.*?)</a>", entry[0])
        name = name_match.group(1) if name_match else "Unknown"

        # 2. Extract Miles (The improved multi-match regex)
        val_str = str(entry[1])
        mile_match = re.search(r"([\d\.]+)\s*(?:mi|miles|mile)", val_str, re.IGNORECASE)

        if mile_match:
            miles = float(mile_match.group(1))
        else:
            # Fallback for copper26 and others
            fallback = re.search(r"(?:Mile|Distance|CP):\s*([\d\.]+)", val_str, re.IGNORECASE)
            miles = float(fallback.group(1)) if fallback else 0.0

        # 3. Extract Metadata
        meta_match = re.search(r"value='(.*?)'", entry[0])
        gender, category = "", ""
        if meta_match:
            parts = meta_match.group(1).split(',')
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
        # The most important part: a real browser string
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        
        # Tells the server what kind of content you can handle
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        
        # Crucial: TrackLeaders often checks if you actually came from their domain
        "Referer": f"https://trackleaders.com/{race_id}/",
        
        # Mimics a real browser's language settings
        "Accept-Language": "en-US,en;q=0.9",
        
        # Tells the server you can handle compressed data (saves bandwidth)
        "Accept-Encoding": "gzip, deflate, br",
        
        # Helps bypass some automated bot detection
        "Upgrade-Insecure-Requests": "1",
        "Sec-Fetch-Dest": "document",
        "Sec-Fetch-Mode": "navigate",
        "Sec-Fetch-Site": "same-origin",
        "Sec-Fetch-User": "?1",
        "Cache-Control": "max-age=0"
    }

    try:
        session = requests.Session()
        
        # 1. Fetch the Follow Page
        resp = session.get(f"{base_url}f.php", headers=headers, timeout=10)
        
        # 2. Extract the 'spots' variable
        # We use a simpler regex that is less picky about spaces/tabs
        spots_match = re.search(r"var\s+spots\s*=\s*(\[\[.*?\]\]);", resp.text, re.DOTALL)
        
        # 3. If that fails (like for Florida 500 sometimes), check the .js file
        if not spots_match:
            js_url = f"https://trackleaders.com/{race_id}spots.js"
            js_resp = session.get(js_url, headers=headers, timeout=10)
            spots_match = re.search(r"var\s+spots\s*=\s*(\[\[.*?\]\]);", js_resp.text, re.DOTALL)

        if not spots_match:
            return jsonify({"error": "Data array not found in PHP or JS"}), 500

        import json
        # We replace single quotes with double quotes for valid JSON loading 
        # (common issue with JS arrays)
        json_string = spots_match.group(1).replace("'", '"')
        raw_data = json.loads(json_string)
        
        riders = extract_riders_from_html(raw_data)
        riders.sort(key=lambda x: x['m'], reverse=True)

        cache[race_id] = {'timestamp': now, 'data': riders}
        return jsonify(riders)

    except Exception as e:
        return jsonify({"error": str(e)}), 500