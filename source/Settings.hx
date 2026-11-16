package;

import flixel.FlxG;

class Settings
{
    public static inline var SPEED_MIN:Float = 0.01;
    public static inline var SPEED_MAX:Float = 100;

    public static inline var CAPPED_FPS:Int = 100;
    public static inline var UNCAPPED_FPS:Int = 10000;

    public static var speed:Float = 1;
    public static var uncappedFps:Bool = false;
    public static var countdownSec:Int = 3;
    public static var voices:Bool = true;
    public static var hitsounds:Bool = true;
    public static var hitsoundVolume:Float = 0.5;
    public static var showStats:Bool = true;
    public static var showClock:Bool = true;
    public static var loadPacing:Float = 1.0;

    public static function applyFramerate():Void
    {
        var fps = uncappedFps ? UNCAPPED_FPS : CAPPED_FPS;

        FlxG.fixedTimestep = false;

        if (fps > FlxG.updateFramerate)
        {
            FlxG.updateFramerate = fps;
            FlxG.drawFramerate = fps;
        }
        else
        {
            FlxG.drawFramerate = fps;
            FlxG.updateFramerate = fps;
        }
    }
}
