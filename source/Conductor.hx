package;

class Conductor
{
    public static var bpm:Int = 120;
    public static var crochet:Float = (60 / bpm) * 1000;
    public static var stepCrochet:Float = crochet / 4;

    public static var songPosition:Float = 0;
    public static var lastSongPos:Float = 0;

    public static var offset:Float = 0;

    public static var maxCatchupMs:Float = crochet;

    public static function changeBPM(newBpm:Int):Void
    {
        bpm = newBpm;
        crochet = (60 / bpm) * 1000;
        stepCrochet = crochet / 4;
        maxCatchupMs = crochet;
    }

    public static function reset():Void
    {
        songPosition = 0;
        lastSongPos = 0;
    }

    public static function update(audioPositionMs:Null<Float>, elapsedSec:Float):Float
    {
        lastSongPos = songPosition;

        if (audioPositionMs != null && audioPositionMs >= 0)
            songPosition = audioPositionMs + offset;
        else
            songPosition += clampCatchup(elapsedSec * 1000);

        return songPosition;
    }

    public static inline function clampCatchup(elapsedMs:Float):Float
    {
        return elapsedMs > maxCatchupMs ? maxCatchupMs : elapsedMs;
    }
}
