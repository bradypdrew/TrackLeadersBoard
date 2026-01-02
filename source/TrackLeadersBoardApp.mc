import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class TrackLeadersBoardApp extends Application.AppBase {
    var mView;

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() {
        mView = new TrackLeadersBoardView();
        // Return only the view in the array
        return [ mView ] as [Views];
    }

    function getSettingsView() {
        var menu = new WatchUi.Menu2({:title=>"Board Settings"});
        
        menu.addItem(new WatchUi.MenuItem("Filter Category", "Current: " + Application.Properties.getValue("RacerCategory"), "cat", null));
        menu.addItem(new WatchUi.MenuItem("Filter Gender", "Current: " + Application.Properties.getValue("RacerGender"), "gen", null));
        menu.addItem(new WatchUi.MenuItem("Highlight Rider", "Current: " + Application.Properties.getValue("RacerName"), "high", null));

        return [ menu, new TrackLeadersBoardMenuDelegate(mView) ] as [Views, InputDelegates];
    }
        
    // This forces the screen to redraw the moment settings are updated
    function onSettingsChanged() {
        WatchUi.requestUpdate(); 
    }
}

function getApp() as TrackLeadersBoardApp {
    return Application.getApp() as TrackLeadersBoardApp;
}