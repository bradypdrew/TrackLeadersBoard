import Toybox.Activity;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;
import Toybox.Graphics;

class TrackLeadersBoardView extends WatchUi.DataField {
    // GLOBAL VARIABLES (Accessible by all functions in this class)
    private var secondCounter = 0;
    private var fetchInterval = 30; // 10 minutes in seconds
    private var riders = null;
    private var lastUpdateStr = "Never";

    function initialize() {
        DataField.initialize();
        //{riders = [
        //    {"n"=>"S. Perez", "m"=>532.3},
        //    {"n"=>"N. DeHaan", "m"=>510.5},
        //    {"n"=>"P. Wickward", "m"=>485.2},
        //    {"n"=>"J. Schlitter", "m"=>450.0},
        //    {"n"=>"I. Micklisch", "m"=>420.1},
        //    {"n"=>"K. Woodward", "m"=>380.5},
        //    {"n"=>"B. Drew", "m"=>350.2},
        //    {"n"=>"C. Iordan", "m"=>310.8},
        //    {"n"=>"D. Serra", "m"=>290.4},
        //    {"n"=>"D. Haluza", "m"=>250.6}
        //] as Array<Dictionary>;
        
        // Initial fetch when the app starts
        fetchRiderData();
    }

    function fetchRiderData() {
        var raceID = Application.Properties.getValue("RaceID");
        // We point to a middleware/proxy because Garmin cannot parse raw HTML
        var url = "https://your-api-proxy.com/trackleaders/" + raceID; 

        var options = {
            :httpMethod => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        System.println("Fetching new data...");
        Communications.makeWebRequest(url, null, options, method(:onReceive));
    }

    function onReceive(responseCode as Number, data as Dictionary or String or Null) as Void {
        System.println("Response Code: " + responseCode);
        if (responseCode == 200 && data != null) {
            // Success! Update our riders array and refresh the screen
            riders = data as Array<Dictionary>;
            WatchUi.requestUpdate();
        } else {
            // Error handling (e.g., 404, -104 for no phone connection)
            System.println("Error Code: " + responseCode);
        }
    }

    function onUpdate(dc) {
        // Import Settings
        var highlightName = Application.Properties.getValue("RacerName");

        // Update the second counter
        secondCounter = secondCounter + 1;
        if (secondCounter >= fetchInterval) {
            fetchRiderData();
            secondCounter = 0;
        }

        // Clear the clipping region and get the current background color
        dc.clearClip();
        var backgroundColor = getBackgroundColor();
        
        // Clear the screen using that color
        dc.setColor(backgroundColor, backgroundColor);
        dc.clear();

        // Determine the best text color (Foreground)
        // If background is black, use white text. Otherwise, use black text.
        var foregroundColor;
        if (backgroundColor == Graphics.COLOR_BLACK) {
            foregroundColor = Graphics.COLOR_WHITE;
        } else {
            foregroundColor = Graphics.COLOR_BLACK;
        }
        dc.setColor(foregroundColor, Graphics.COLOR_TRANSPARENT);

        var width = dc.getWidth();
        var font = Graphics.FONT_SMALL;
        var rowHeight = dc.getFontHeight(font) + 5;
        var padding = 20;

        // Draw Header
        dc.setColor(foregroundColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(padding, 10, Graphics.FONT_XTINY, "TRACK LEADERS BOARD", Graphics.TEXT_JUSTIFY_LEFT);
        var headerFont = Graphics.FONT_XTINY;
        var fontHeight = dc.getFontHeight(headerFont);
        var headerHeight = fontHeight + 20;
        var footerHeight = 20;
        var usableHeight = dc.getHeight() - headerHeight;
        dc.drawLine(0, headerHeight-10, width, headerHeight-10);

        // If no riders data yet, show "Downloading" message
        if (riders == null) {
            dc.setColor(foregroundColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, headerHeight + (usableHeight / 2), Graphics.FONT_MEDIUM, "Downloading Riders...", Graphics.TEXT_JUSTIFY_CENTER);
            
            // Optional: Draw a "Trying to reach [RaceID]" message below it
            var raceID = Application.Properties.getValue("RaceID");
            dc.drawText(width / 2, headerHeight + (usableHeight / 2) + dc.getFontHeight(Graphics.FONT_MEDIUM)+5, Graphics.FONT_XTINY, "Race: " + raceID, Graphics.TEXT_JUSTIFY_CENTER);
            
            return; // Stop drawing the rest of the UI until data arrives
        }

        // Divide usable space by row height
        // Use .toNumber() to ensure we don't try to show a "partial" rider
        var ridersPerPage = (usableHeight / rowHeight).toNumber();
        if (ridersPerPage < 1) { 
            ridersPerPage = 1; 
        }

        // Draw Leaderboard Rows
        var startIdx = 0; //Update this to implement scrolling later
        var totalRiders = riders.size() as Number;
        for (var i = 0; i < ridersPerPage; i++) {
            var currentRiderIdx = (startIdx + i) as Number;
            if (currentRiderIdx >= totalRiders) { break; }

            var yPos = headerHeight + (i * rowHeight);
            
            // Use 'as' to stop the warning
            var rider = riders[currentRiderIdx];

            // Use .get() and 'as' for the values too
            var name = rider.get("n") as String;
            var nameSearch = name.toUpper();
            var rawMiles = rider.get("m");
            var mileStr = "0.0";
            if (rawMiles instanceof Lang.Float || rawMiles instanceof Lang.Double) {
                // "%.1f" means: 1 decimal place, floating point
                mileStr = rawMiles.format("%.1f"); 
            } else {
                // Fallback if it's already a string or integer
                mileStr = rawMiles.toString();
            }

            // Highlight logic
            if (highlightName != null && highlightName.length() > 0) {
                highlightName = highlightName.toUpper();
                if (nameSearch.find(highlightName) != null) {
                    dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
                    dc.fillRoundedRectangle(
                        5,                     // x: slightly in from the left
                        yPos - 4,                    // y: centered on text
                        dc.getWidth() - 10, // width: leave padding on both sides
                        rowHeight - 2,                          // height
                        8                 // radius
                    );
                    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);                  
                } else {
                    dc.setColor(foregroundColor, Graphics.COLOR_TRANSPARENT);
                }
            } else {
                dc.setColor(foregroundColor, Graphics.COLOR_TRANSPARENT);
            }

            dc.drawText(10, yPos, font, name, Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(width - 10, yPos, font, mileStr, Graphics.TEXT_JUSTIFY_RIGHT);
        }

        // Add a timestamp at the bottom

        // Draw a subtle separator line
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(10, footerHeight - 5, width - 10, footerHeight - 5);

        // Draw the timestamp
        var statusText = "Last Update: " + lastUpdateStr;
        dc.drawText(width / 2, footerHeight, Graphics.FONT_XTINY, statusText, Graphics.TEXT_JUSTIFY_CENTER);
    }
}