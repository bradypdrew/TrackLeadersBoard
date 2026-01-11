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
    current_time = time.time()

    # Check if we have a valid cache
    if race_id in cache:
        entry = cache[race_id]
        if current_time - entry['timestamp'] < CACHE_DURATION:
            print(f"Returning CACHED data for {race_id}")
            return jsonify(entry['data'])

    # If no cache, scrape TrackLeaders
    # TrackLeaders often checks if you came from the main race page
    base_url = f"https://trackleaders.com/{race_id}"
    
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "application/json, text/javascript, */*; q=0.01",
        "Accept-Language": "en-US,en;q=0.9",
        "Referer": base_url, # This is crucial for bypassing 403s on JSON endpoints
        "X-Requested-With": "XMLHttpRequest"
    }

    try:
        # Using a session can help handle cookies if TrackLeaders starts requiring them
        session = requests.Session()
        

        # TRY THE MODERN JSON FIRST
        resp = session.get(f"{base_url}/sortlist.json", headers=headers, timeout=15)
        if resp.status_code == 200:
            raw_json = resp.json()
            # If it's valid sortlist.json, we still pass it through our parser 
            # to keep the output format consistent for Garmin
            riders = extract_riders_from_html(raw_json.get("data", []))
        
        else:
            # STEP 2: Try f.php (The "Legacy/Copper26" way)
            resp = session.get(f"{base_url}f.php", headers=headers, timeout=10)
            if resp.status_code != 200:
                return jsonify({"error": "Race not found"}), 404
            
            # A. Check if data is already in the HTML
            spots_match = re.search(r"var\s+(?:spots|markers|points)\s*=\s*(\[.*?\]);", resp.text, re.DOTALL)
            
            # B. If NOT in HTML, find the .js file link
            if not spots_match:
                js_link_match = re.search(r'src="([^"]*?spots\.js)"', resp.text)
                if js_link_match:
                    js_url = f"https://trackleaders.com/{js_link_match.group(1)}"
                    js_resp = session.get(js_url, headers=headers, timeout=10)
                    spots_match = re.search(r"var\s+(?:spots|markers|points)\s*=\s*(\[.*?\]);", js_resp.text, re.DOTALL)

            if not spots_match:
                return jsonify({"error": "Could not find spot data in PHP or JS file"}), 500
            
            import json
            raw_data_list = json.loads(spots_match.group(1))
            riders = extract_riders_from_html(raw_data_list)

        # Final Processing
        riders.sort(key=lambda x: x['m'], reverse=True)
        cache[race_id] = {'timestamp': current_time, 'data': riders}
        return jsonify(riders)

    except Exception as e:
        return jsonify({"error": str(e)}), 500