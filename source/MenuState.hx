package;

import flixel.FlxG;
import flixel.FlxState;
import flixel.text.FlxText.FlxTextAlign;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import openfl.system.System;
import sys.FileSystem;

class MenuState extends FlxState
{
    static inline var ITEM_START:Int = 0;
    static inline var ITEM_SPEED:Int = 1;
    static inline var ITEM_COUNTDOWN:Int = 2;
    static inline var ITEM_VOICES:Int = 3;
    static inline var ITEM_HITSOUNDS:Int = 4;
    static inline var ITEM_HITSOUND_VOL:Int = 5;
    static inline var ITEM_STATS:Int = 6;
    static inline var ITEM_FPS:Int = 7;
    static inline var ITEM_CLOCK:Int = 8;
    static inline var ITEM_LOADING:Int = 9;
    static inline var ITEM_QUIT:Int = 10;
    static inline var ITEM_COUNT:Int = 11;

    static inline var FIRST_ITEM_Y:Float = 185;
    static inline var ITEM_SPACING:Float = 38;
    static inline var HOLD_DELAY:Float = 0.4;
    static inline var HOLD_REPEAT:Float = 0.06;

    var texts:Array<FlxText> = [];
    var selected:Int = 0;
    var holdDir:Int = 0;
    var holdTime:Float = 0;
    var warnText:FlxText;
    var missing:String = null;

    override public function create():Void
    {
        super.create();

        Settings.applyFramerate();

        var greyboxColor:FlxColor = FlxColor.fromRGB(64, 64, 64);
        FlxG.cameras.bgColor = greyboxColor;
        bgColor = greyboxColor;

        var title = new FlxText(0, 90, FlxG.width, "iutk engine");
        title.alignment = FlxTextAlign.CENTER;
        title.size = 56;
        title.color = FlxColor.WHITE;
        add(title);

        for (i in 0...ITEM_COUNT)
        {
            var t = new FlxText(0, FIRST_ITEM_Y + i * ITEM_SPACING, FlxG.width, "");
            t.alignment = FlxTextAlign.CENTER;
            t.size = 32;
            add(t);
            texts.push(t);
        }

        warnText = new FlxText(0, 625, FlxG.width, "");
        warnText.alignment = FlxTextAlign.CENTER;
        warnText.size = 18;
        warnText.color = FlxColor.RED;
        add(warnText);

        var hint = new FlxText(0, 680, FlxG.width,
            "up/down: select    left/right: change (shift: fine steps)    enter: confirm    esc: quit");
        hint.alignment = FlxTextAlign.CENTER;
        hint.size = 14;
        hint.color = 0xFFBBBBBB;
        add(hint);

        checkFiles();
        refresh();
    }

    function checkFiles():Void
    {
        var instPath = PlayState.AUDIO_DIR + "/Inst.ogg";
        var chartPath = PlayState.DATA_DIR + "/Chart.bin";

        missing = null;

        if (!FileSystem.exists(chartPath))
            missing = chartPath;
        else if (!FileSystem.exists(instPath))
            missing = instPath;

        warnText.text = missing != null ? 'missing file: $missing (you can still change options)' : "";
    }

    function refresh():Void
    {
        for (i in 0...ITEM_COUNT)
        {
            var label:String;
            var value:String = null;

            switch (i)
            {
                case ITEM_START:
                    label = "start";
                case ITEM_SPEED:
                    label = "scroll speed";
                    value = Std.string(Settings.speed);
                case ITEM_COUNTDOWN:
                    label = "start countdown";
                    value = Settings.countdownSec <= 0 ? "off" : Settings.countdownSec + "s";
                case ITEM_VOICES:
                    label = "voices";
                    value = Settings.voices ? "on" : "off";
                case ITEM_HITSOUNDS:
                    label = "hitsounds (experimental)";
                    value = Settings.hitsounds ? "on" : "off";
                case ITEM_HITSOUND_VOL:
                    label = "hitsound volume";
                    value = Math.round(Settings.hitsoundVolume * 100) + "%";
                case ITEM_STATS:
                    label = "debug stats";
                    value = Settings.showStats ? "on" : "off";
                case ITEM_FPS:
                    label = "frame rate";
                    value = Settings.uncappedFps ? "uncapped" : "capped (" + Settings.CAPPED_FPS + ")";
                case ITEM_CLOCK:
                    label = "real-time clock";
                    value = Settings.showClock ? "on" : "off";
                case ITEM_LOADING:
                    label = "loading screen";
                    value = Settings.loadPacing > 0 ? "realistic" : "instant";
                default:
                    label = "quit";
            }

            var s = label;
            if (value != null)
                s += ": " + (i == selected ? "<  " + value + "  >" : value);

            var t = texts[i];
            t.text = (i == selected ? "> " : "  ") + s + (i == selected ? " <" : "  ");
            t.color = i == selected ? FlxColor.YELLOW : FlxColor.WHITE;
        }
    }

    function heldDir():Int
    {
        if (FlxG.keys.pressed.LEFT || FlxG.keys.pressed.A)
            return -1;
        if (FlxG.keys.pressed.RIGHT || FlxG.keys.pressed.D)
            return 1;
        return 0;
    }

    function move(dir:Int):Void
    {
        selected = (selected + dir + ITEM_COUNT) % ITEM_COUNT;
        holdDir = heldDir();
        holdTime = 0;
        refresh();
    }

    inline function isRepeatable(item:Int):Bool
    {
        return item == ITEM_SPEED || item == ITEM_COUNTDOWN || item == ITEM_HITSOUND_VOL;
    }

    function change(dir:Int):Void
    {
        switch (selected)
        {
            case ITEM_SPEED:
                var step = FlxG.keys.pressed.SHIFT ? 0.1 : 0.5;
                var v = Math.round((Settings.speed + dir * step) * 10) / 10;
                Settings.speed = Math.max(Settings.SPEED_MIN, Math.min(Settings.SPEED_MAX, v));
            case ITEM_COUNTDOWN:
                var v = Settings.countdownSec + dir;
                Settings.countdownSec = v < 0 ? 0 : (v > 10 ? 10 : v);
            case ITEM_VOICES:
                Settings.voices = !Settings.voices;
            case ITEM_HITSOUNDS:
                Settings.hitsounds = !Settings.hitsounds;
            case ITEM_HITSOUND_VOL:
                var step = FlxG.keys.pressed.SHIFT ? 0.01 : 0.05;
                var v = Math.round((Settings.hitsoundVolume + dir * step) * 100) / 100;
                Settings.hitsoundVolume = Math.max(0, Math.min(1, v));
            case ITEM_STATS:
                Settings.showStats = !Settings.showStats;
            case ITEM_CLOCK:
                Settings.showClock = !Settings.showClock;
            case ITEM_LOADING:
                Settings.loadPacing = Settings.loadPacing > 0 ? 0.0 : 1.0;
            case ITEM_FPS:
                Settings.uncappedFps = !Settings.uncappedFps;
                Settings.applyFramerate();
            default:
                return;
        }
        refresh();
    }

    function activate():Void
    {
        switch (selected)
        {
            case ITEM_START:
                checkFiles();
                if (missing != null)
                    return;
                FlxG.switchState(new PlayState());
            case ITEM_VOICES, ITEM_HITSOUNDS, ITEM_STATS, ITEM_FPS, ITEM_CLOCK, ITEM_LOADING:
                change(1);
            case ITEM_QUIT:
                System.exit(0);
            default:
        }
    }

    override public function update(elapsed:Float):Void
    {
        super.update(elapsed);

        if (FlxG.keys.justPressed.UP || FlxG.keys.justPressed.W)
            move(-1);
        if (FlxG.keys.justPressed.DOWN || FlxG.keys.justPressed.S)
            move(1);

        var dir = heldDir();

        if (dir == 0)
        {
            holdDir = 0;
            holdTime = 0;
        }
        else if (dir != holdDir)
        {
            holdDir = dir;
            holdTime = 0;
            change(dir);
        }
        else if (isRepeatable(selected))
        {
            holdTime += elapsed;
            while (holdTime > HOLD_DELAY)
            {
                holdTime -= HOLD_REPEAT;
                change(dir);
            }
        }

        if (FlxG.keys.justPressed.ENTER || FlxG.keys.justPressed.SPACE)
            activate();

        if (FlxG.keys.justPressed.ESCAPE)
            System.exit(0);
    }
}
