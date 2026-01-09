from flask import Flask, jsonify
from flask_cors import CORS
import requests
import re

app = Flask(__name__)
CORS(app)

@app.route('/race/<race_id>')
def scrape_trackleaders(race_id):
    url = f"https://trackleaders.com/spot/{race_id}/sortlist.json"
    headers = {"User-Agent": "Mozilla/5.0"}

    try:
        response = requests.get(url, headers=headers, timeout=10)
        if response.status_code != 200:
            return {"error": "TrackLeaders returned status " + str(response.status_code)}
        try:
            data = response.json()
        except:
            # This means it got HTML instead of JSON
            return {"error": "Invalid data received from TrackLeaders. Check RaceID."}
        raw_data = response.json()
        riders = []

        for entry in raw_data.get("data", []):
            if len(entry) >= 2:
                # 1. EXTRACT NAME
                name_match = re.search(r"onClick='clrac\(\);'>(.*?)</a>", entry[0])
                name = name_match.group(1) if name_match else "Unknown"

                # 2. EXTRACT MILES
                mile_match = re.search(r"'>([\d\.]+)\s*mi", entry[1])
                miles = float(mile_match.group(1)) if mile_match else (999.0 if "FIN" in entry[1] else 0.0)

                # 3. EXTRACT METADATA (Gender & Category)
                # Look for the value attribute in the hidden input
                meta_match = re.search(r"value='(.*?)'", entry[0])
                gender = ""
                category = ""
                
                if meta_match:
                    parts = meta_match.group(1).split(',')
                    # Index 4 is usually Gender, Index 7 is usually Category
                    if len(parts) > 4:
                        gender = parts[4].strip()
                    if len(parts) > 7:
                        category = parts[7].strip()

                riders.append({
                    "n": name, 
                    "m": miles, 
                    "g": gender,   # "Men" or "Women"
                    "c": category  # "Solo Unsupported", "2-person Relay", etc.
                })

        riders.sort(key=lambda x: x['m'], reverse=True)
        return jsonify(riders)

    except Exception as e:
        return jsonify({"error": str(e)}), 500