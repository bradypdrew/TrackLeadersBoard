from flask import Flask, jsonify
from flask_cors import CORS
import html
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
        # Check for data presence
        if len(entry) < 2:
            continue

        # --- EXTRACT NAME ---
        # 1. DECODE THE UNICODE & HTML
        # This converts \u003c... into <... and &amp; into &
        raw_name_html = entry[0].encode('utf-8').decode('unicode-escape')
        raw_name_html = html.unescape(raw_name_html)

        # 2. EXTRACT THE TERMINAL NAME
        # Trackleaders maps follow a pattern: [Icon][Fav][History Link]Name
        # The name is the only text not inside an attribute.
        # This regex finds all text between > and <
        text_segments = re.findall(r'>([^<]+)<', raw_name_html)
        
        if text_segments:
            # We filter out segments that are just whitespace
            # and take the LAST one, which is the actual rider name.
            clean_segments = [t.strip() for t in text_segments if len(t.strip()) > 1]
            name = clean_segments[-1] if clean_segments else "Unknown"
        else:
            # Fallback: Strip all tags if no segments found
            name = re.sub(r'<[^>]+>', '', raw_name_html).strip()

        # --- EXTRACT MILES ---
        # We check column 2 (index 2) first for Copper-style, 
        # then fallback to column 1 for older formats.
        val_miles_raw = ""
        if len(entry) > 2:
            val_miles_raw = str(entry[2]) # Column 3 (Index 2)
        else:
            val_miles_raw = str(entry[1]) # Column 2 (Index 1)

        # Regex: find any decimal number followed by 'mi' or 'miles'
        mile_match = re.search(r"([\d\.]+)\s*(?:mi|miles|mile)", val_miles_raw, re.IGNORECASE)
        
        if mile_match:
            miles = float(mile_match.group(1))
        elif "FIN" in val_miles_raw or "Finish" in val_miles_raw:
            miles = 999.0
        else:
            # Final fallback: just look for ANY decimal number in the mile column
            fallback = re.search(r"([\d\.]+)", val_miles_raw)
            miles = float(fallback.group(1)) if fallback else 0.0

        # --- EXTRACT METADATA (Gender & Category) ---
        # We look for value='ID,Type,Rank,Status,Gender,Category...'
        gender = ""
        category = ""
        meta_match = re.search(r"value='(.*?)'", val_name_raw)
        
        if meta_match:
            parts = meta_match.group(1).split(',')
            # Index logic for Florida 500:
            # Usually: [0:ID, 1:Main, 2:Rank, 3:Age, 4:Gender, 7:Category]
            if len(parts) > 4:
                gender = parts[4].strip()
            if len(parts) > 7:
                category = parts[7].strip()
            # If parts[7] is empty, sometimes Category is at index 5 or 6 
            # depending on the specific race template
            if not category and len(parts) > 5:
                category = parts[5].strip()

        riders.append({
            "n": name, 
            "m": miles, 
            "g": gender, 
            "c": category
        })

    return riders

@app.route('/race/<race_id>')
def scrape_trackleaders(race_id):
    now = time.time()
    if race_id in cache and (now - cache[race_id]['timestamp'] < CACHE_DURATION):
        return jsonify(cache[race_id]['data'])

    # Clean the race_id just in case
    race_id = race_id.strip().lower()
    base_url = f"https://trackleaders.com/{race_id}"
    json_url = f"https://trackleaders.com/spot/{race_id}/sortlist.json"
    
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
        response = session.get(json_url, headers=headers, timeout=10)
        if response.status_code != 200:
            return jsonify({"error": f"TrackLeaders returned status {response.status_code}"}), response.status_code

        # Parse JSON response to populate riders if successful
        raw_data = response.json()
        riders = extract_riders_from_html(raw_data.get("data", []))
        riders.sort(key=lambda x: x['m'], reverse=True)

        # Cache the result
        cache[race_id] = {'timestamp': now, 'data': riders}

        return jsonify(riders)

    except Exception as e:
        return jsonify({"error": str(e)}), 500