import Toybox.WatchUi;
import Toybox.Application;
import Toybox.Lang;

class TrackLeadersSettingsMenu extends WatchUi.Menu2 {
    function initialize(view) {
        Menu2.initialize({:title=>"Filter Category"});
        
        var allRiders = view.riders as Array;
        if (allRiders != null) {
            var menu = new WatchUi.Menu2({:title=>"Filter Category"});
            
            // 2. Use a Dictionary to find UNIQUE category names
            var uniqueCategories = {};
            for (var i = 0; i < allRiders.size(); i++) {
                var r = allRiders[i] as Dictionary;
                var cat = r.get("c") as String;
                if (cat != null && cat.length() > 0) {
                    uniqueCategories[cat] = true; 
                }
            }

            // Add "Show All" option first
            menu.addItem(
                new WatchUi.MenuItem(
                    "Show All" as Lang.String, 
                    null, 
                    "ALL" as Lang.String, 
                    null
                )
            );

            // Add the unique categories found in the data
            var keys = uniqueCategories.keys();
            for (var j = 0; j < keys.size(); j++) {
                var categoryName = keys[j] as Lang.String;
                menu.addItem(
                    new WatchUi.MenuItem(
                        categoryName,    // Label displayed to user
                        "Racer Category", // Sub-label
                        categoryName,    // ID passed to onSelect
                        null
                    )
                );
            }
            
            // Note: Since this class IS the menu, use 'addItem' directly:
            addItem(new WatchUi.MenuItem("Show All", null, "ALL", null));
        }
    }
}

class TrackLeadersBoardMenuDelegate extends WatchUi.Menu2InputDelegate {
    var mView;

    function initialize(view) {
        Menu2InputDelegate.initialize();
        mView = view;
    }

    function onSelect(item) {
        var id = item.getId() as String;
        var currentMenu = WatchUi.getCurrentView()[0] as WatchUi.Menu2;

        if (id.equals("cat")) {
            pushCategoryMenu(currentMenu);
        } else if (id.equals("gen")) {
            pushGenderMenu(currentMenu);
        } else if (id.equals("high")) {
            pushHighlightMenu(currentMenu);
        }
    }

    // --- SUB-MENU: GENDER ---
    function pushGenderMenu(parentMenu) {
        var menu = new WatchUi.Menu2({:title=>"Gender"});
        menu.addItem(new WatchUi.MenuItem("Show All", null, "ALL", null));
        var riders = mView.riders as Array;
        if (riders != null) {
            var uniqueCategories = {};
            for (var i = 0; i < riders.size(); i++) {
                var rider = riders[i] as Dictionary;
                var cat = rider.get("g") as String;
                if (cat != null) { uniqueCategories[cat] = true; }
            }

            var keys = uniqueCategories.keys();
            for (var j = 0; j < keys.size(); j++) {
                var label = keys[j] as Lang.String;
                menu.addItem(new WatchUi.MenuItem(label, null, label, null));
            }
        }
        
        WatchUi.pushView(menu, new GenderSelectionDelegate(mView, parentMenu), WatchUi.SLIDE_LEFT);
    }

    // --- SUB-MENU: HIGHLIGHT ---
    function pushHighlightMenu(parentMenu) {
        var menu = new WatchUi.Menu2({:title=>"Highlight Rider"});
        menu.addItem(new WatchUi.MenuItem("None", null, "NONE", null));
        
        var riders = mView.riders as Array;
        if (riders != null) {
            for (var i = 0; i < riders.size(); i++) {
                var name = (riders[i] as Dictionary).get("n") as String;
                menu.addItem(new WatchUi.MenuItem(name, null, name, null));
            }
        }
        WatchUi.pushView(menu, new HighlightSelectionDelegate(mView, parentMenu), WatchUi.SLIDE_LEFT);
    }

    // --- SUB-MENU: CATEGORY ---
    function pushCategoryMenu(parentMenu) {
        var menu = new WatchUi.Menu2({:title=>"Category"});
        menu.addItem(new WatchUi.MenuItem("Show All", null, "ALL", null));
        
        var riders = mView.riders as Array;
        if (riders != null) {
            var uniqueCategories = {};
            for (var i = 0; i < riders.size(); i++) {
                var cat = (riders[i] as Dictionary).get("c");
                if (cat != null) { uniqueCategories[cat] = true; }
            }

            var keys = uniqueCategories.keys();
            for (var j = 0; j < keys.size(); j++) {
                var label = keys[j] as Lang.String;
                menu.addItem(new WatchUi.MenuItem(label, null, label, null));
            }
        }
        WatchUi.pushView(menu, new CategorySelectionDelegate(mView, parentMenu), WatchUi.SLIDE_LEFT);
    }
}

class GenderSelectionDelegate extends WatchUi.Menu2InputDelegate {
    var mView;
    var mParentMenu;

    function initialize(view, parentMenu) {
        Menu2InputDelegate.initialize();
        mView = view;
        mParentMenu = parentMenu;
    }

    function onSelect(item) {
        var gender = item.getId() as String;

        // Save the actual property
        Application.Properties.setValue("RacerGender", gender);
        
        // Find the item in the main menu and update its sub-label
        var idx = mParentMenu.findItemById("gen");
        if (idx != -1) {
            var mainMenuItem = mParentMenu.getItem(idx) as WatchUi.MenuItem;
            mainMenuItem.setSubLabel("Current: " + gender);
        }

        // Reset the view index and go back
        mView.startIdx = 0;
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

class HighlightSelectionDelegate extends WatchUi.Menu2InputDelegate {
    var mView;
    var mParentMenu;

    function initialize(view, parentMenu) {
        Menu2InputDelegate.initialize();
        mView = view;
        mParentMenu = parentMenu;
    }

    function onSelect(item) {
        var name = item.getId() as String;

        // Save the actual property
        Application.Properties.setValue("RacerName", name);
        
        // Find the item in the main menu and update its sub-label
        var idx = mParentMenu.findItemById("high");
        if (idx != -1) {
            var mainMenuItem = mParentMenu.getItem(idx) as WatchUi.MenuItem;
            mainMenuItem.setSubLabel("Current: " + name);
        }

        // Reset the view index and go back
        mView.startIdx = 0;
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

class CategorySelectionDelegate extends WatchUi.Menu2InputDelegate {
    var mView;
    var mParentMenu;

    function initialize(view, parentMenu) {
        Menu2InputDelegate.initialize();
        mView = view;
        mParentMenu = parentMenu;
    }

    function onSelect(item) {
        var category = item.getId() as String;
        // Save the actual property
        Application.Properties.setValue("RacerCategory", category);
        
        // Find the item in the main menu and update its sub-label
        var idx = mParentMenu.findItemById("cat");
        if (idx != -1) {
            var mainMenuItem = mParentMenu.getItem(idx) as WatchUi.MenuItem;
            mainMenuItem.setSubLabel("Current: " + category);
        }

        // Reset the view index and go back
        mView.startIdx = 0;
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}