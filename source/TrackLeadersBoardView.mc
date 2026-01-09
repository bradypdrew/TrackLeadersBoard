import Toybox.Activity;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;
import Toybox.Graphics;

class TrackLeadersBoardView extends WatchUi.DataField {
    // GLOBAL VARIABLES
    public var riders = null as Array<Dictionary>; // Array to hold rider data
    public var startIdx = 0; // Used for scrolling
    public var width = 0;
    private var secondCounter = 0;
    private var fetchInterval = 600; // Time (in sec) between data fetches
    private var lastUpdateStr = "Never";
    private var _speed = 0.0;
    private var _power3s = 0;
    private var _powerSamples = [0, 0, 0] as Array<Number>;
    private var _sampleIdx = 0;
    private var _distance = 0.0;
    private var _gearStr = "--";

    function initialize() {
        DataField.initialize();
        // Initial fetch when the app starts
        fetchRiderData();
    }

    function compute(info) {
        // 1. Speed (convert m/s to mph)
        if (info has :currentSpeed && info.currentSpeed != null) {
            _speed = info.currentSpeed * 2.23694;
        }

        // 2. Distance (convert meters to miles)
        if (info has :elapsedDistance && info.elapsedDistance != null) {
            _distance = info.elapsedDistance * 0.000621371;
        }

        // 3. 3-Second Power
        if (info has :currentPower && info.currentPower != null) {
            // 1. Store the newest sample
            (_powerSamples as Array<Number>)[_sampleIdx] = info.currentPower as Number;
            _sampleIdx = (_sampleIdx + 1) % 3; // Cycle through 0, 1, 2

            // 2. Calculate the average of the 3 samples
            _power3s = ((_powerSamples as Array<Number>)[0] + (_powerSamples as Array<Number>)[1] + (_powerSamples as Array<Number>)[2]) / 3;
        } else {
            _power3s = 0;
        }

        // 4. Derailleur Gear Indices (e.g., Front 2, Rear 5)
        // Ratio (e.g., 52/11  = 4.7)
        if (info has :frontDerailleurSize && info.frontDerailleurSize != null && 
            info has :rearDerailleurSize && info.rearDerailleurSize != null) {
            var ratio = info.frontDerailleurSize.toFloat() / info.rearDerailleurSize.toFloat();
            _gearStr = ratio.format("%.1f");
        } 
        // Gear Positions (e.g., 2-11)
        else if (info has :frontDerailleurIndex && info.frontDerailleurIndex != null && info has :rearDerailleurIndex && info.rearDerailleurIndex != null) {
            _gearStr = info.frontDerailleurIndex.format("%d") + "-" + info.rearDerailleurIndex.format("%d");
        } else {
            _gearStr = "--";
        }
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
        } else if (responseCode == 403) {
            lastUpdateStr = "Blocked by Server";
            WatchUi.requestUpdate();
            System.println("Error Code: " + responseCode);
        } else {
            lastUpdateStr = "Error: " + responseCode;
            WatchUi.requestUpdate();
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
        var font = Graphics.FONT_MEDIUM;
        var smallFont = Graphics.FONT_SMALL;
        var largeFont = Graphics.FONT_LARGE;
        var rowHeight = dc.getFontHeight(font) + 5;
        var padding = 10;
        var dashboardHeight = 2*dc.getFontHeight(largeFont) + 5;

        // Draw Header
        var clock = System.getClockTime();
        var timeStr = clock.hour.format("%02d") + ":" + clock.min.format("%02d");
        dc.setColor(foregroundColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(padding, 10, smallFont, timeStr, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(width - padding, 10, smallFont, "TRACKLEADERS BOARD", Graphics.TEXT_JUSTIFY_RIGHT);
        var headerHeight = dc.getFontHeight(smallFont) + 20;
        var footerHeight = headerHeight - 15;
        var usableHeight = height - headerHeight - footerHeight - dashboardHeight;
        dc.drawLine(0, headerHeight-10, width, headerHeight-10);

        // Draw Dashboard
        dc.setPenWidth(2);
        var dashboardY = height - dashboardHeight;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(0, dashboardY, width, dashboardY);
        dc.drawLine(width / 2, dashboardY, width / 2, height);
        dc.drawLine(0, dashboardY + dashboardHeight/2, width, dashboardY + dashboardHeight/2);
        dc.setColor(foregroundColor, Graphics.COLOR_TRANSPARENT);
        var data = [
            {:label => "MPH",   :val => _speed.format("%.1f")},
            {:label => "3S PWR",:val => _power3s.toString()},
            {:label => "DIST",  :val => _distance.format("%.1f")},
            {:label => "GEAR",  :val => _gearStr}
        ];
        for (var i = 0; i < 4; i++) {
            // Calculate cell center points
            var col = i % 2;
            var row = i / 2;
            
            var labelX = (col == 0) ? width * 0.02 : width * 0.52;
            var dataX = (col == 0) ? width * 0.48 : width * 0.98;
            var centerY = (row == 0) ? dashboardY + (dashboardHeight * 0.05) : dashboardY + (dashboardHeight * 0.55);

            // Draw Label 
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(labelX, centerY, smallFont, data[i][:label], Graphics.TEXT_JUSTIFY_LEFT);

            // Draw Value
            dc.setColor(foregroundColor, Graphics.COLOR_TRANSPARENT);
            // Use a larger font since we have more room now
            dc.drawText(dataX, centerY, largeFont, data[i][:val], Graphics.TEXT_JUSTIFY_RIGHT);
        }

        // If no riders data yet, show "Downloading" message
        if (riders == null) {
            dc.setColor(foregroundColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, headerHeight + (usableHeight / 2), Graphics.FONT_MEDIUM, "Downloading Riders...", Graphics.TEXT_JUSTIFY_CENTER);
            
            // Optional: Draw a "Trying to reach [RaceID]" message below it
            var raceID = Application.Properties.getValue("RaceID");
            dc.drawText(width / 2, headerHeight + (usableHeight / 2) + dc.getFontHeight(Graphics.FONT_MEDIUM)+5, Graphics.FONT_SMALL, "Race: " + raceID, Graphics.TEXT_JUSTIFY_CENTER);
            
            return; // Stop drawing the rest of the UI until data arrives
        }

        // Filter riders based on gender and category, if specified
        // Normalize: Treat null or empty as "ALL"
        var gFilter = (genderProp == null || genderProp.length() == 0) ? "ALL" : genderProp.toUpper();
        var cFilter = (categoryProp == null || categoryProp.length() == 0) ? "ALL" : categoryProp.toUpper();
        var filteredRiders = [];
        for (var i = 0; i < (riders as Array<Dictionary>).size(); i++) {
            var r = (riders as Array<Dictionary>)[i] as Dictionary;
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
        var virtualTotal = shouldScroll ? (totalRiders + 2) : totalRiders; // Add a few blank rows for spacing when scrolling
        
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
        dc.drawLine(10, height - footerHeight - dashboardHeight - 5, width - 10, height - footerHeight - dashboardHeight - 5);

        // Draw the timestamp
        var statusText = "Last Update: " + lastUpdateStr;
        dc.drawText(width / 2, height - footerHeight - dashboardHeight, smallFont, statusText, Graphics.TEXT_JUSTIFY_CENTER);
    }
}