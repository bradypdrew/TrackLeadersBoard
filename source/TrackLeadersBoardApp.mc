import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class TrackLeadersBoardApp extends Application.AppBase {

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
        return [ new TrackLeadersBoardView() ];
    }
        
    // This forces the screen to redraw the moment settings are updated
    function onSettingsChanged() {
        WatchUi.requestUpdate(); 
    }
}

function getApp() as TrackLeadersBoardApp {
    return Application.getApp() as TrackLeadersBoardApp;
}