from flask import Flask, jsonify
import requests
from bs4 import BeautifulSoup
from flask_cors import CORS

app = Flask(__name__)
CORS(app) # This ensures your Garmin device doesn't get blocked by security policies

@app.route('/race/<race_id>')
def scrape_trackleaders(race_id):
    # TrackLeaders 'f' pages are usually the mobile-friendly/lite versions
    url = f"https://trackleaders.com/{race_id}f"
    
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        }
        response = requests.get(url, headers=headers, timeout=10)
        soup = BeautifulSoup(response.text, 'html.parser')
        
        riders = []
        # Find the table - TrackLeaders usually uses <tr> tags for rows
        rows = soup.find_all('tr')
        
        for row in rows:
            cols = row.find_all('td')
            if len(cols) >= 3:
                # This logic depends on the specific race table layout
                # Usually: Col 0 = Rank, Col 1 = Name, Col 2 = Miles
                name = cols[1].text.strip()
                miles_text = cols[2].text.strip()
                
                # Try to convert miles to a float for the Garmin
                try:
                    miles = float(miles_text)
                except ValueError:
                    miles = 0.0
                #miles = miles_text
                
                riders.append({"n": name, "m": miles})
        
        # Sort by miles descending (leader first)
        riders.sort(key=lambda x: x['m'], reverse=True)
        
        return jsonify(riders)

    except Exception as e:
        return jsonify({"error": str(e)}), 500

# Required for Vercel
def handler(event, context):
    return app(event, context)