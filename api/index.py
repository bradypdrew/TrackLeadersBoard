from flask import Flask, jsonify
from flask_cors import CORS
import requests

app = Flask(__name__)
CORS(app)

@app.route('/race/<race_id>')
def scrape_trackleaders(race_id):
    # This is the direct data source used by the TrackLeaders sidebar
    url = f"https://trackleaders.com/spot/{race_id}/sortlist.json"
    headers = {"User-Agent": "Mozilla/5.0"}

    try:
        response = requests.get(url, headers=headers, timeout=10)
        
        # If the JSON doesn't exist, the race ID might be wrong
        if response.status_code != 200:
            return jsonify({"error": "Race data not found"}), 404

        data = response.json()
        riders = []

        # TrackLeaders sortlist.json structure:
        # aaData is a list of lists. 
        # Usually: index 1 = Name, index 3 = Miles
        for entry in data.get("aaData", []):
            if len(entry) >= 4:
                # TrackLeaders puts HTML tags in the JSON (like <b>Name</b>)
                # We need to strip those out
                name = entry[1].replace('<b>','').replace('</b>','')
                
                # Miles is usually a string like "450.2"
                try:
                    miles = float(entry[3])
                except (ValueError, TypeError):
                    miles = 0.0
                
                riders.append({"n": name, "m": miles})

        # Sort by miles descending
        riders.sort(key=lambda x: x['m'], reverse=True)
        return jsonify(riders)

    except Exception as e:
        return jsonify({"error": str(e)}), 500