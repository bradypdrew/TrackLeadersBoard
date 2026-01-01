from flask import Flask, jsonify
from flask_cors import CORS
import requests
import re

app = Flask(__name__)
CORS(app)

@app.route('/race/<race_id>')
def scrape_trackleaders(race_id):
    # This matches the specific Florida 500 path we found
    url = f"https://trackleaders.com/spot/{race_id}/sortlist.json"
    headers = {"User-Agent": "Mozilla/5.0"}

    try:
        response = requests.get(url, headers=headers, timeout=10)
        if response.status_code != 200:
            return jsonify({"error": "Race data not found"}), 404

        raw_data = response.json()
        riders = []

        # The key in your provided JSON is "data"
        for entry in raw_data.get("data", []):
            if len(entry) >= 2:
                # 1. EXTRACT NAME
                # We look for the text between the last </a> and the next <a> or <div>
                # Your JSON shows name like: ...onClick='clrac();'>DAVID KODNER</a>
                name_html = entry[0]
                name_match = re.search(r"onClick='clrac\(\);'>(.*?)</a>", name_html)
                name = name_match.group(1) if name_match else "Unknown"

                # 2. EXTRACT MILES
                # Your JSON shows: ...00475015'>295.2 mi
                mile_html = entry[1]
                mile_match = re.search(r"'>([\d\.]+)\s*mi", mile_html)
                
                if mile_match:
                    miles = float(mile_match.group(1))
                elif "FIN" in mile_html:
                    # If they finished, we mark them at 500 (or a high number) 
                    # so they stay at the top of the leaderboard
                    miles = 999.0 
                else:
                    miles = 0.0
                
                riders.append({"n": name, "m": miles})

        # Sort by miles (Finished/High miles first)
        riders.sort(key=lambda x: x['m'], reverse=True)
        return jsonify(riders)

    except Exception as e:
        return jsonify({"error": str(e)}), 500