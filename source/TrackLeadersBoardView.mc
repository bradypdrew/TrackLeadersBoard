import Toybox.Activity;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;
import Toybox.Graphics;

class TrackLeadersBoardView extends WatchUi.DataField {
    // GLOBAL VARIABLES (Accessible by all functions in this class)
    public var riders = null as Array<Dictionary>; // Array to hold rider data
    public var startIdx = 0; // Used for scrolling
    public var width = 0;
    private var secondCounter = 0;
    private var fetchInterval = 30; // 10 minutes in seconds
    private var lastUpdateStr = "Never";

    function initialize() {
        DataField.initialize();
        // Initial fetch when the app starts
        fetchRiderData();
    }

    function fetchRiderData() {
        var raceID = Application.Properties.getValue("RaceID");
        // We point to a middleware/proxy because Garmin cannot parse raw HTML
        var url = "https://track-leaders-board-6hj2.vercel.app/race/" + raceID; 

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
            var clock = System.getClockTime();
            // Format as HH:MM (e.g., 14:05 or 2:05)
            lastUpdateStr = clock.hour.format("%02d") + ":" + clock.min.format("%02d");
            WatchUi.requestUpdate();
        } else {
            // Error handling (e.g., 404, -104 for no phone connection)
            System.println("Error Code: " + responseCode);
        }
    }

    function onUpdate(dc) {
        // Scrolling configuration
        var slowScrollSpeed = 5; // Scroll speed in seconds when a highlight is set
        var fastScrollSpeed = 2; // Scroll speed in seconds when no highlight is set
        var highlightFound = false;

        // Import Settings
        var highlightName = Application.Properties.getValue("RacerName");
        var genderProp = Application.Properties.getValue("RacerGender");
        var categoryProp = Application.Properties.getValue("RacerCategory");

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
        var height = dc.getHeight();
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
        var usableHeight = height - headerHeight;
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

        // Filter riders based on gender and category, if specified
        // Normalize: Treat null or empty as "ALL"
        var gFilter = (genderProp == null || genderProp.length() == 0) ? "ALL" : genderProp.toUpper();
        var cFilter = (categoryProp == null || categoryProp.length() == 0) ? "ALL" : categoryProp.toUpper();
        var filteredRiders = [];
        for (var i = 0; i < riders.size(); i++) {
            var r = riders[i] as Dictionary;
            var rG = r.get("g");
            var rC = r.get("c");
            var rGender = (rG != null) ? (rG as String).toUpper() : "";
            var rCategory = (rC != null) ? (rC as String).toUpper() : "";

            // Match if filter is "ALL" OR if it's an exact match
            var genderMatch = (gFilter.equals("ALL") || rGender.equals(gFilter));
            var categoryMatch = (cFilter.equals("ALL") || rCategory.equals(cFilter));

            if (genderMatch && categoryMatch) {
                filteredRiders.add(r);
            }
        }

        var totalRiders = filteredRiders.size();
        if (totalRiders == 0) {
            dc.drawText(width/2, height/2, font, "No Matches Found", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // Divide usable space by row height
        // Use .toNumber() to ensure we don't try to show a "partial" rider
        var ridersPerPage = (usableHeight / rowHeight).toNumber();
        if (ridersPerPage < 1) { 
            ridersPerPage = 1; 
        }

        // Determine if scrolling is needed
        var shouldScroll = (totalRiders > ridersPerPage);

        if (!shouldScroll) {
            startIdx = 0; // Lock to the top
        }

        // Draw Leaderboard Rows
        var virtualTotal = shouldScroll ? (totalRiders + 3) : totalRiders; // Add 3 blank rows for spacing when scrolling
        
        // Only loop as many times as we have riders if the list is short
        var iterations = shouldScroll ? ridersPerPage : totalRiders;
        for (var i = 0; i < iterations; i++) {
            var yPos = headerHeight + (i * rowHeight);
            var virtualIdx = (startIdx + i) % virtualTotal;
            
            if (virtualIdx < totalRiders) {
                var rider = filteredRiders[virtualIdx] as Dictionary;
                // Use .get() and 'as' for the values too
                var name = rider.get("n") as String;
                var nameSearch = name.toUpper();

                // Format miles to 1 decimal place
                var rawMiles = rider.get("m");
                var mileStr = "0.0";
                if (rawMiles instanceof Lang.Float || rawMiles instanceof Lang.Double) {
                    // "%.1f" means: 1 decimal place, floating point
                    mileStr = rawMiles.format("%.1f"); 
                } else {
                    // Fallback if it's already a string or integer
                    mileStr = rawMiles.toString();
                }

                // Truncate the name if it's too long
                var mileWidth = dc.getTextWidthInPixels(mileStr, font);
                var nameMaxWidth = width - mileWidth - 30; // 10px padding on left, 10px on right, 10px between
                var displayName = name;
                if (dc.getTextWidthInPixels(displayName, font) > nameMaxWidth) {
                    displayName = displayName + "...";
                    while (displayName.length() > 2 && dc.getTextWidthInPixels(displayName, font) > nameMaxWidth) {
                        displayName = displayName.substring(0, displayName.length() - 4) + "...";
                    }
                }

                // Highlight logic
                if (highlightName != null && highlightName.length() > 0) {
                    highlightName = highlightName.toUpper();
                    if (nameSearch.find(highlightName) != null) {
                        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
                        dc.fillRoundedRectangle(
                            5,                     // x: slightly in from the left
                            yPos - 4,                    // y: centered on text
                            width - 10, // width: leave padding on both sides
                            rowHeight - 2,                          // height
                            8                 // radius
                        );
                        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);                  
                        highlightFound = true;
                    } else {
                        dc.setColor(foregroundColor, Graphics.COLOR_TRANSPARENT);
                    }
                } else {
                    dc.setColor(foregroundColor, Graphics.COLOR_TRANSPARENT);
                }

                dc.drawText(10, yPos, font, displayName, Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(width - 10, yPos, font, mileStr, Graphics.TEXT_JUSTIFY_RIGHT);
            }
        }

        // Update scrolling index
        if (highlightFound) {
            if (secondCounter % slowScrollSpeed == 0) {
                //startIdx = (startIdx + 1) % totalRiders;
                startIdx = (startIdx + 1) % virtualTotal;
            }
        } else {
            if (secondCounter % fastScrollSpeed == 0) {
                //startIdx = (startIdx + 1) % totalRiders;
                startIdx = (startIdx + 1) % virtualTotal;
            }
        }

        // Add a timestamp at the bottom

        // Draw a subtle separator line
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(10, height - footerHeight - 5, width - 10, height - footerHeight - 5);

        // Draw the timestamp
        var statusText = "Last Update: " + lastUpdateStr;
        dc.drawText(width / 2, height - footerHeight, Graphics.FONT_XTINY, statusText, Graphics.TEXT_JUSTIFY_CENTER);
    }
}