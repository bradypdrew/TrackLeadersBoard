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
        # 1. Clean up quotes and backslashes first
        raw_val = str(entry[0]).replace('\\"', '"').replace("\\'", "'")

        # 2. TrackLeaders names are almost always inside the last <a> tag.
        # We split by '</a>' and take the piece immediately to the left of it.
        if "</a>" in raw_val:
            # Get the part before the last </a>
            parts = raw_val.split("</a>")
            # Take the last link part
            last_link_content = parts[-2] 
            # The name is everything after the last '>' in that link content
            name = last_link_content.split(">")[-1].strip()
        else:
            # Fallback for plain text names: Split by > and <
            name = raw_val.split(">")[-1].split("<")[0].strip()

        # 3. Final Clean: Strip any remaining bold tags or stray quotes
        name = re.sub(r'<[^>]+>', '', name).replace('"', '').replace('\\', '').strip()

        # Add these inside the loop to debug
        #print(f"DEBUG RAW: {entry[0][:100]}...") # See the first 100 chars
        #print(f"DEBUG EXTRACTED NAME: {name}")

        # --- EXTRACT MILES (Dynamic Search) ---
        miles = 0.0
        found_miles = False

        # Loop through every column in this rider's data row
        for col_value in entry:
            col_str = str(col_value)
            
            # 1. Strip HTML tags to see the visible text
            visible_text = re.sub(r'<[^>]+>', '', col_str).strip()

            # 2. Look for the "mi" or "miles" marker
            mile_match = re.search(r"([\d\.]+)\s*(?:mi|miles|mile)", visible_text, re.IGNORECASE)
            
            if mile_match:
                miles = float(mile_match.group(1))
                found_miles = True
                break # We found it, stop looking in other columns
            
            # 3. Handle Finishers
            elif "FIN" in visible_text.upper():
                miles = 9999.0
                found_miles = True
                break

        # 4. Fallback (If no column had "mi", try to find a number in the 3rd or 4th col)
        if not found_miles:
            # Check column 2 then 3
            for i in [2, 3]:
                if len(entry) > i:
                    fallback_text = re.sub(r'<[^>]+>', '', str(entry[i]))
                    fallback_match = re.search(r"([\d\.]+)", fallback_text)
                    if fallback_match:
                        miles = float(fallback_match.group(1))
                        break

        # --- EXTRACT METADATA (Gender & Category) ---
        # We look for value='ID,Type,Rank,Status,Gender,Category...'
        gender = ""
        category = ""
        meta_match = re.search(r"value='(.*?)'", str(entry[0]))
        
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