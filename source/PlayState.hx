package;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.group.FlxGroup;
import flixel.sound.FlxSound;
import flixel.text.FlxText.FlxTextAlign;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import haxe.ds.Vector;
import openfl.Assets;
import openfl.display.BitmapData;
import openfl.display.Tile;
import openfl.display.Tilemap;
import openfl.display.Tileset;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.media.Sound;
import openfl.system.System;
import sys.FileSystem;
import sys.thread.Mutex;
import sys.thread.Thread;

typedef LoadStep =
{
    var label:String;
    var weight:Float;
    var minSec:Float;
    var run:Void->Void;
}

class PlayState extends FlxState
{
    static inline var DEST_SIZE:Float = 104;
    static inline var DEST_SIZE_INT:Int = 104;
    static inline var STRUM_Y:Float = 50;
    static inline var NOTE_BOTTOM_CULL:Float = 690;
    static inline var SYNC_THRESHOLD_MS:Float = 15;
    static inline var ENTRY_RING_START:Int = 1 << 12;
    static inline var HUD_REFRESH_SEC:Float = 0.25;

    static var lanesX:Array<Float> = [92, 204, 316, 428, 728, 840, 952, 1064];

    static var angles:Array<Float> = [0, -90, 90, 180];

    static var noteGraphicPaths:Array<String> = [
        "assets/images/0.png",
        "assets/images/1.png",
        "assets/images/2.png",
        "assets/images/3.png"
    ];

    static var laneDirs:Array<String> = ["LEFT", "DOWN", "UP", "RIGHT"];

    var scrollSpeed:Float = 1;
    var notes:NoteBuffer;
    var notesHead:Int = 0;
    var totalNotes:U64 = new U64();
    var hitNotes:U64 = new U64();
    var scannedNotes:U64 = new U64();
    var visibleNotesNow:U64 = new U64();
    var frameOppHits:U64 = new U64();
    var framePlayerHits:U64 = new U64();

    var noteTileset:Tileset;
    var noteTilemap:Tilemap;

    var entryTiles:Vector<Tile>;
    var entryPos:Vector<Int>;
    var entryMask:Int = 0;
    var entryHead:Int = 0;
    var entryTail:Int = 0;
    var freeTiles:Array<Tile> = [];
    var runValid:Bool = false;
    var runPos:Int = 0;
    var runMask:Int = 0;
    var visibleEnd:Int = 0;
    var hudElapsed:Float = 0;
    var hudFrames:Int = 0;
    var enteringScratch:Array<Tile> = [];
    var noteTileScale:Float;

    var dad:Character;
    var bf:Character;

    var music:FlxSound;
    var voices:Array<FlxSound> = [];
    var musicStarted:Bool = false;
    var waitingToStart:Bool = true;
    var startPromptText:FlxText;

    var fpsText:FlxText;
    var renderedText:FlxText;
    var progressText:FlxText;
    var memText:FlxText;

    var frameTimeMs:Float = 0;
    var maxFrameTimeMs:Float = 0;
    var frameTimeText:FlxText;
    var tileCountText:FlxText;
    var lastTileCountShown:Int = -1;

    var oppNpsBucket:U64 = new U64();
    var oppNpsPrevBucket:Float = 0;
    var playerNpsBucket:U64 = new U64();
    var playerNpsPrevBucket:Float = 0;
    var npsBucketElapsed:Float = 0;
    var oppNpsDisplay:Float = 0;
    var playerNpsDisplay:Float = 0;

    var oppNpsText:FlxText;
    var playerNpsText:FlxText;

    var lastVisibleNotes:U64 = new U64(-2, -2);
    var lastHitNotes:U64 = new U64(-2, -2);
    var lastOppNpsDisplay:Float = -1;
    var lastPlayerNpsDisplay:Float = -1;

    static inline var SPEED_MIN:Float = Settings.SPEED_MIN;
    static inline var SPEED_MAX:Float = Settings.SPEED_MAX;
    static inline var SLIDER_X:Float = 8;
    static inline var SLIDER_Y:Float = 640;
    static inline var SLIDER_WIDTH:Float = 200;
    static inline var SLIDER_HEIGHT:Float = 6;
    static inline var HANDLE_WIDTH:Float = 14;
    static inline var HANDLE_HEIGHT:Float = 20;

    var sliderHandle:FlxSprite;
    var speedText:FlxText;
    var draggingSlider:Bool = false;

    static inline var TIMEBAR_W:Float = 340;
    static inline var TIMEBAR_H:Float = 8;
    static inline var TIMEBAR_X:Float = 470;
    static inline var TIMEBAR_Y:Float = 30;

    var timeBarTrack:FlxSprite;
    var timeBarFill:FlxSprite;
    var timeText:FlxText;
    var songLengthMs:Float = 0;
    var lengthFromChart:Bool = false;
    var instSound:Sound;

    var songEnded:Bool = false;
    var endShown:Bool = false;
    var endText:FlxText;
    var lastTimeSecShown:Int = -1;

    var countingDown:Bool = false;
    var countdownMs:Float = 0;
    var countdownText:FlxText;
    var lastCountdownShown:Int = -1;

    static inline var LOAD_BAR_W:Float = 640;
    static inline var LOAD_BAR_H:Float = 18;
    static inline var CHART_SHARE:Float = 0.6;
    static inline var SORT_SHARE:Float = 0.1;
    static inline var CHART_MIN_SEC:Float = 1.4;

    var loading:Bool = true;
    var loadFailed:Bool = false;
    var leaving:Bool = false;
    var loadingGroup:FlxGroup;
    var loadBarFill:FlxSprite;
    var loadStatusText:FlxText;
    var loadPercentText:FlxText;
    var loadDetailText:FlxText;
    var loadShownProgress:Float = 0;
    var loadFinishing:Bool = false;
    var loadFinishHoldUntil:Float = -1;
    var stutterNextAt:Float = 0;
    var loadStartTime:Float = 0;
    var chartFileBytes:Float = 0;
    var chartPhaseDone:Bool = false;
    var loadSteps:Array<LoadStep> = [];
    var loadStepsTotalWeight:Float = 0;
    var loadStepsDoneWeight:Float = 0;
    var loadStepCount:Int = 0;
    var stepStart:Float = -1;
    var stepRan:Bool = false;

    var clockText:FlxText;
    var loadClockText:FlxText;
    var lastClockTick:Int = -1;
    var playWallStart:Float = -1;
    var playWallEnd:Float = -1;

    var workerMutex:Mutex = new Mutex();
    var workerDone:Bool = false;
    var workerError:String = null;
    var workerSorting:Bool = false;
    var workerChartProgress:Float = 0;
    var workerCancelled:Bool = false;

    public static inline var AUDIO_DIR:String = "assets/audio";
    static var voiceFiles:Array<String> = ["Voices.ogg", "Voices-Player.ogg", "Voices-Opponent.ogg"];
    public static inline var DATA_DIR:String = "assets/data";

    override public function create():Void
    {
        super.create();

        Conductor.changeBPM(120);

        scrollSpeed = clampSpeed(Settings.speed);

        var t:Float;

        t = Sys.time();
        buildCharacters();
        trace('buildCharacters: ${(Sys.time() - t) * 1000} ms');

        t = Sys.time();
        buildStrums();
        trace('buildStrums: ${(Sys.time() - t) * 1000} ms');

        t = Sys.time();
        buildNotePool();
        trace('buildNotePool: ${(Sys.time() - t) * 1000} ms');

        t = Sys.time();
        buildOverlay();
        buildTimeBar();
        trace('buildOverlay: ${(Sys.time() - t) * 1000} ms');

        t = Sys.time();
        buildSlider();
        trace('buildSlider: ${(Sys.time() - t) * 1000} ms');

        buildStartPrompt();
        startPromptText.visible = false;
        buildCountdownText();
        buildEndText();
        applyStatsVisibility();

        Settings.applyFramerate();

        var greyboxColor:FlxColor = FlxColor.fromRGB(64, 64, 64);
        FlxG.cameras.bgColor = greyboxColor;
        bgColor = greyboxColor;

        buildLoadingScreen();
        beginLoading();
    }

    function beginLoading():Void
    {
        loadStartTime = Sys.time();

        var instPath = audioPath("Inst.ogg");
        var chartPath = dataPath("Chart.bin");

        if (!FileSystem.exists(chartPath))
        {
            failLoading('missing file: $chartPath');
            return;
        }
        if (!FileSystem.exists(instPath))
        {
            failLoading('missing file: $instPath');
            return;
        }

        chartFileBytes = FileSystem.stat(chartPath).size;

        trace('loading binary chart: $chartPath');
        Thread.create(function() chartWorker(chartPath));
    }

    function chartWorker(binPath:String):Void
    {
        var err:String = null;

        try
        {
            var start = Sys.time();
            notes = ChartBinary.load(binPath, onChartProgress);
            trace('loadChart: ${(Sys.time() - start) * 1000} ms');

            workerMutex.acquire();
            workerSorting = true;
            workerMutex.release();

            start = Sys.time();
            sortNotesIfNeeded();
            trace('sortNotesIfNeeded: ${(Sys.time() - start) * 1000} ms');
        }
        catch (e:Dynamic)
        {
            err = Std.string(e);
        }

        workerMutex.acquire();
        workerError = err;
        workerDone = true;
        workerMutex.release();
    }

    function onChartProgress(p:Float):Void
    {
        workerMutex.acquire();
        workerChartProgress = p;
        var cancelled = workerCancelled;
        workerMutex.release();

        if (cancelled)
            throw "cancelled";
    }

    function onChartLoaded():Void
    {
        totalNotes.copyFrom(notes.total);
        initEntryRing();

        trace('loaded ${totalNotes} notes (${notes.length} cells)');

        loadSteps.push({
            label: "verifying chart integrity...",
            weight: 0.3,
            minSec: 0.8,
            run: verifyChart
        });

        var instPath = audioPath("Inst.ogg");
        loadSteps.push({
            label: "decoding inst.ogg...",
            weight: 0.5,
            minSec: 1.0,
            run: function()
            {
                instSound = Sound.fromFile(instPath);
                music = FlxG.sound.load(instSound, 1, false);
            }
        });

        var voicePaths = new Array<String>();
        if (Settings.voices)
        {
            for (f in voiceFiles)
                if (FileSystem.exists(audioPath(f)))
                    voicePaths.push(f);
        }

        if (voicePaths.length == 0)
            trace('no voice files used (${voiceFiles.join(", ")}) - instrumental only');

        for (f in voicePaths)
        {
            var path = audioPath(f);
            loadSteps.push({
                label: 'decoding $f...',
                weight: 0.35 / voicePaths.length,
                minSec: 0.6,
                run: function()
                {
                    voices.push(FlxG.sound.load(Sound.fromFile(path), 1, false));
                }
            });
        }

        if (Settings.hitsounds && Settings.hitsoundVolume > 0)
        {
            loadSteps.push({
                label: "rendering hitsounds...",
                weight: 0.4,
                minSec: 0.8,
                run: function()
                {
                    var track = HitsoundTrack.build(notes, instSound.length, Settings.hitsoundVolume);
                    if (track != null)
                        voices.push(track);
                }
            });
        }

        loadSteps.push({
            label: "finishing up...",
            weight: 0.15,
            minSec: 0.7,
            run: function()
            {
                System.gc();
                Conductor.reset();
            }
        });

        loadStepCount = loadSteps.length;
        for (s in loadSteps)
            loadStepsTotalWeight += s.weight;
    }

    function verifyChart():Void
    {
        var n = notes.length;
        var lanes = notes.lanes;

        var badLanes = 0;
        for (i in 0...n)
        {
            if (lanes.get(i) > 7)
                badLanes++;
        }

        if (badLanes > 0)
            throw '$badLanes cells have an invalid lane';
        if (!isRangeSorted(0, n))
            throw 'chart is not sorted';

        trace('verifyChart: $n cells OK');
    }

    function updateLoading(elapsed:Float):Void
    {
        if (loadFailed)
            return;

        var pacing = Settings.loadPacing;
        var elapsedSec = Sys.time() - loadStartTime;
        var elapsedStr = '${roundTo(elapsedSec, 1)}s';
        var target:Float = 0;
        var status:String = "";
        var detail:String = "";
        var tickedNow = false;

        if (loadFinishing)
        {
            stutterAdvance(1.0, Sys.time(), elapsed);
            loadBarFill.scale.x = Math.max(loadShownProgress, 0.0005);
            setTextIfChanged(loadStatusText, "finishing up...");
            setTextIfChanged(loadPercentText, Math.round(loadShownProgress * 100) + "%");

            if (loadShownProgress >= 0.999)
            {
                if (loadFinishHoldUntil < 0)
                    loadFinishHoldUntil = Sys.time() + 0.35 * pacing;
                else if (Sys.time() >= loadFinishHoldUntil)
                    finishLoading();
            }
            return;
        }

        if (!chartPhaseDone)
        {
            workerMutex.acquire();
            var done = workerDone;
            var err = workerError;
            var sorting = workerSorting;
            var cp = workerChartProgress;
            workerMutex.release();

            if (done && err != null)
            {
                failLoading('failed to load chart: $err');
                return;
            }

            var chartMin = CHART_MIN_SEC * pacing;
            var timeFrac = chartMin > 0 ? elapsedSec / chartMin : 1.0;
            var realFrac = (done || sorting) ? 1.0 : cp;
            var shown = Math.min(1.0, Math.min(realFrac, timeFrac));

            if (done && timeFrac >= 1)
            {
                onChartLoaded();
                chartPhaseDone = true;
                target = CHART_SHARE + SORT_SHARE;
                status = 'chart loaded: ${totalNotes.toGroupedString()} notes';
                detail = 'elapsed: $elapsedStr';
            }
            else if (shown >= 1)
            {
                var dots = [".", "..", "..."][Std.int(elapsedSec * 3) % 3];
                target = CHART_SHARE;
                status = 'sorting notes$dots';
                detail = 'elapsed: $elapsedStr';
            }
            else
            {
                target = shown * CHART_SHARE;
                status = "reading chart...";
                detail = 'chart: ${formatBytes(shown * chartFileBytes)} / ${formatBytes(chartFileBytes)}   |   elapsed: $elapsedStr';
            }
        }
        else
        {
            var current = loadSteps[0];
            var stepMin = current.minSec * pacing;

            if (stepStart < 0)
            {
                stepStart = Sys.time();
                stepRan = false;
            }
            else if (!stepRan)
            {
                try
                {
                    current.run();
                }
                catch (e:Dynamic)
                {
                    failLoading('${current.label} failed: $e');
                    return;
                }
                stepRan = true;
            }

            var stepElapsed = stepStart < 0 ? 0.0 : Sys.time() - stepStart;

            if (stepRan && stepElapsed >= stepMin)
            {
                loadStepsDoneWeight += current.weight;
                loadSteps.shift();
                stepStart = -1;
                stepRan = false;

                if (loadSteps.length == 0)
                {
                    if (pacing > 0 && loadShownProgress < 0.995)
                    {
                        loadFinishing = true;
                        return;
                    }
                    finishLoading();
                    return;
                }

                current = loadSteps[0];
                stepElapsed = 0;
                stepMin = current.minSec * pacing;
            }

            var frac = stepMin > 0 ? Math.min(1.0, stepElapsed / stepMin) : (stepRan ? 1.0 : 0.0);
            if (!stepRan && frac > 0.9)
                frac = 0.9;

            var stepNo = loadStepCount - loadSteps.length + 1;
            var stepsFrac = (loadStepsDoneWeight + current.weight * frac) / loadStepsTotalWeight;
            target = CHART_SHARE + SORT_SHARE + (1 - CHART_SHARE - SORT_SHARE) * stepsFrac;
            status = current.label;
            detail = 'step $stepNo/$loadStepCount   |   notes: ${totalNotes.toGroupedString()}   |   elapsed: $elapsedStr';
        }

        tickedNow = stutterAdvance(target, Sys.time(), elapsed);
        loadBarFill.scale.x = Math.max(loadShownProgress, 0.0005);

        setTextIfChanged(loadStatusText, status.toLowerCase());
        setTextIfChanged(loadPercentText, Math.round(loadShownProgress * 100) + "%");

        if (tickedNow || Settings.loadPacing <= 0)
            setTextIfChanged(loadDetailText, detail.toLowerCase());
    }

    function stutterAdvance(target:Float, nowSec:Float, elapsed:Float):Bool
    {
        var pacing = Settings.loadPacing;
        if (pacing <= 0)
        {
            loadShownProgress += (target - loadShownProgress) * Math.min(1, elapsed * 10);
            return true;
        }

        if (nowSec < stutterNextAt)
            return false;

        var gap = target - loadShownProgress;
        if (gap <= 0.0005)
            return false;

        var chunk = Math.min(gap, gap * (0.25 + Math.random() * 0.6) + 0.003);
        loadShownProgress += chunk;

        var r = Math.random();
        var wait = r < 0.12 ? 0.45 + Math.random() * 0.8
            : r < 0.5 ? 0.12 + Math.random() * 0.25
            : 0.02 + Math.random() * 0.08;
        stutterNextAt = nowSec + wait * pacing;

        #if sys
        if (Math.random() < 0.12)
            Sys.sleep(0.03 + Math.random() * 0.09);
        #end

        return true;
    }

    function finishLoading():Void
    {
        loading = false;
        loadingGroup.visible = false;
        loadingGroup.active = false;

        resolveSongLength();
        updateTimeBar(0);

        startPromptText.visible = true;

        var loadedMs:Float = (Sys.time() - loadStartTime) * 1000;
        trace('DONE LOADING!! Loaded in ${Math.round(loadedMs * 1000) / 1000} milliseconds.');
    }

    function failLoading(msg:String):Void
    {
        loadFailed = true;
        trace(msg);

        loadStatusText.color = FlxColor.RED;
        loadStatusText.text = msg;
        loadPercentText.text = "";
        loadDetailText.text = "press esc to go back to the menu";
        loadBarFill.color = FlxColor.RED;
    }

    inline function setTextIfChanged(t:FlxText, s:String):Void
    {
        if (t.text != s)
            t.text = s;
    }

    function buildLoadingScreen():Void
    {
        loadingGroup = new FlxGroup();

        var cover = new FlxSprite(0, 0);
        cover.makeGraphic(1280, 720, 0xFF202020);
        loadingGroup.add(cover);

        var title = new FlxText(0, 230, 1280, "loading");
        title.alignment = FlxTextAlign.CENTER;
        title.size = 40;
        title.color = FlxColor.WHITE;
        loadingGroup.add(title);

        loadStatusText = new FlxText(0, 300, 1280, "starting...");
        loadStatusText.alignment = FlxTextAlign.CENTER;
        loadStatusText.size = 20;
        loadStatusText.color = FlxColor.WHITE;
        loadingGroup.add(loadStatusText);

        var barX = (1280 - LOAD_BAR_W) / 2;
        var barY:Float = 350;

        var track = new FlxSprite(barX, barY);
        track.makeGraphic(Std.int(LOAD_BAR_W), Std.int(LOAD_BAR_H), 0xFF404040);
        loadingGroup.add(track);

        loadBarFill = new FlxSprite(barX, barY);
        loadBarFill.makeGraphic(Std.int(LOAD_BAR_W), Std.int(LOAD_BAR_H), 0xFF5CE1FF);
        loadBarFill.origin.set(0, 0);
        loadBarFill.scale.x = 0.0005;
        loadingGroup.add(loadBarFill);

        loadPercentText = new FlxText(0, barY + 26, 1280, "0%");
        loadPercentText.alignment = FlxTextAlign.CENTER;
        loadPercentText.size = 18;
        loadPercentText.color = FlxColor.CYAN;
        loadingGroup.add(loadPercentText);

        loadDetailText = new FlxText(0, barY + 62, 1280, "");
        loadDetailText.alignment = FlxTextAlign.CENTER;
        loadDetailText.size = 14;
        loadDetailText.color = 0xFFBBBBBB;
        loadingGroup.add(loadDetailText);

        var hint = new FlxText(0, 680, 1280, "esc: back to menu");
        hint.alignment = FlxTextAlign.CENTER;
        hint.size = 12;
        hint.color = 0xFF888888;
        loadingGroup.add(hint);

        loadClockText = new FlxText(0, 8, 1272, "");
        loadClockText.alignment = FlxTextAlign.RIGHT;
        loadClockText.size = 14;
        loadClockText.color = 0xFFBBBBBB;
        loadClockText.visible = Settings.showClock;
        loadingGroup.add(loadClockText);

        add(loadingGroup);
    }

    function leaveToMenu():Void
    {
        if (leaving)
            return;
        leaving = true;

        workerMutex.acquire();
        workerCancelled = true;
        workerMutex.release();

        if (music != null)
            music.stop();
        for (v in voices)
            v.stop();

        FlxG.switchState(new MenuState());
    }

    function buildTimeBar():Void
    {
        timeText = new FlxText(TIMEBAR_X - 60, 8, TIMEBAR_W + 120, "0:00 / 0:00");
        timeText.alignment = FlxTextAlign.CENTER;
        timeText.size = 14;
        timeText.color = FlxColor.WHITE;
        add(timeText);

        timeBarTrack = new FlxSprite(TIMEBAR_X, TIMEBAR_Y);
        timeBarTrack.makeGraphic(Std.int(TIMEBAR_W), Std.int(TIMEBAR_H), 0xFF202020);
        add(timeBarTrack);

        timeBarFill = new FlxSprite(TIMEBAR_X, TIMEBAR_Y);
        timeBarFill.makeGraphic(Std.int(TIMEBAR_W), Std.int(TIMEBAR_H), 0xFF5CE1FF);
        timeBarFill.origin.set(0, 0);
        timeBarFill.scale.x = 0.0005;
        add(timeBarFill);
    }

    function formatTime(ms:Float):String
    {
        var total = Std.int(Math.max(0, ms) / 1000);
        var h = Std.int(total / 3600);
        var m = Std.int((total % 3600) / 60);
        var s = total % 60;
        var ss = (s < 10 ? "0" : "") + s;
        if (h > 0)
            return h + ":" + (m < 10 ? "0" : "") + m + ":" + ss;
        return m + ":" + ss;
    }

    function audioLengthMs():Float
    {
        var len:Float = music.length;
        if (len > 0)
            return len;

        len = instSound.length;
        if (len > 0)
            return len;

        return 0;
    }

    function resolveSongLength():Void
    {
        var len = audioLengthMs();
        if (len > 0)
        {
            songLengthMs = len;
            lengthFromChart = false;
        }
        else
        {
            songLengthMs = notes.length > 0 ? notes.positions[notes.length - 1] + 1000 : 0;
            lengthFromChart = true;
        }
        lastTimeSecShown = -1;
    }

    function buildEndText():Void
    {
        endText = new FlxText(0, 300, 1280, "SONG FINISHED\npress enter to return to the menu");
        endText.alignment = FlxTextAlign.CENTER;
        endText.size = 32;
        endText.color = FlxColor.WHITE;
        endText.setBorderStyle(FlxTextBorderStyle.OUTLINE, FlxColor.BLACK, 3);
        endText.visible = false;
        add(endText);
    }

    function showSongEnd():Void
    {
        endShown = true;
        playWallEnd = Sys.time();
        endText.visible = true;

        for (v in voices)
            v.stop();

        timeBarFill.scale.x = 1;
        timeText.text = formatTime(songLengthMs) + " / " + formatTime(songLengthMs);
    }

    function updateTimeBar(nowMs:Float):Void
    {
        if (lengthFromChart && musicStarted)
        {
            var len = audioLengthMs();
            if (len > 0)
            {
                songLengthMs = len;
                lengthFromChart = false;
                lastTimeSecShown = -1;
            }
        }

        var cur = nowMs < 0 ? 0 : nowMs;
        if (songLengthMs > 0 && cur > songLengthMs)
            cur = songLengthMs;

        var ratio = songLengthMs > 0 ? cur / songLengthMs : 0;
        timeBarFill.scale.x = Math.max(ratio, 0.0005);

        var sec = Std.int(cur / 1000);
        if (sec != lastTimeSecShown)
        {
            lastTimeSecShown = sec;
            timeText.text = formatTime(cur) + " / " + formatTime(songLengthMs);
        }
    }

    function buildCountdownText():Void
    {
        countdownText = new FlxText(0, 290, 1280, "");
        countdownText.alignment = FlxTextAlign.CENTER;
        countdownText.size = 96;
        countdownText.color = FlxColor.WHITE;
        countdownText.setBorderStyle(FlxTextBorderStyle.OUTLINE, FlxColor.BLACK, 4);
        countdownText.visible = false;
        add(countdownText);
    }

    function beginCountdown():Void
    {
        if (Settings.countdownSec <= 0)
        {
            startPlayback();
            return;
        }

        countingDown = true;
        countdownMs = Settings.countdownSec * 1000.0;
        lastCountdownShown = -1;
        countdownText.visible = true;
        updateCountdownText();
    }

    function updateCountdownText():Void
    {
        var secs = Math.ceil(countdownMs / 1000);
        if (secs != lastCountdownShown)
        {
            lastCountdownShown = secs;
            countdownText.text = Std.string(secs);
        }

        var frac = countdownMs / 1000 - (secs - 1);
        countdownText.alpha = 0.35 + 0.65 * frac;
    }

    function startPlayback():Void
    {
        countingDown = false;
        countdownText.visible = false;

        musicStarted = true;
        playWallStart = Sys.time();
        Conductor.reset();

        music.onComplete = function() { songEnded = true; };
        music.play();

        for (v in voices)
            v.play();
    }

    function applyStatsVisibility():Void
    {
        var show = Settings.showStats;
        clockText.visible = Settings.showClock;
        renderedText.visible = show;
        fpsText.visible = show;
        memText.visible = show;
        frameTimeText.visible = show;
        tileCountText.visible = show;
    }

    static inline function npsString(v:Float):String
    {
        return U64.fromFloat(v).toDisplayString();
    }

    inline function roundTo(v:Float, decimals:Int):Float
    {
        var mult = Math.pow(10, decimals);
        return Math.fround(v * mult) / mult;
    }

    function formatBytes(bytes:Float):String
    {
        if (bytes >= 1073741824)
            return roundTo(bytes / 1073741824, 2) + " GB";
        else
            return roundTo(bytes / 1048576, 1) + " MB";
    }

    function audioPath(name:String):String
    {
        return AUDIO_DIR + "/" + name;
    }

    function dataPath(name:String):String
    {
        return DATA_DIR + "/" + name;
    }

    function isRangeSorted(start:Int, end:Int):Bool
    {
        var pos = notes.positions;
        var i = start + 1;
        while (i < end)
        {
            if (pos[i] < pos[i - 1])
                return false;
            i++;
        }
        return true;
    }

    function sortNotesIfNeeded():Void
    {
        if (notes.length < 2)
            return;

        if (isRangeSorted(0, notes.length))
            return;

        quickSortNotes(0, notes.length - 1);
    }

    function quickSortNotes(loStart:Int, hiStart:Int):Void
    {
        var pos = notes.positions;
        var stack = new Array<Int>();
        stack.push(loStart);
        stack.push(hiStart);

        while (stack.length > 0)
        {
            var hi = stack.pop();
            var lo = stack.pop();

            while (lo < hi)
            {
                if (hi - lo < 16)
                {
                    insertionSort(lo, hi);
                    break;
                }

                var mid = lo + ((hi - lo) >> 1);
                if (pos[mid] < pos[lo])
                    notes.swap(mid, lo);
                if (pos[hi] < pos[lo])
                    notes.swap(hi, lo);
                if (pos[hi] < pos[mid])
                    notes.swap(hi, mid);
                var pivot = pos[mid];
                notes.swap(mid, hi - 1);

                var i = lo;
                var j = hi - 1;
                while (true)
                {
                    do { i++; } while (pos[i] < pivot);
                    do { j--; } while (pos[j] > pivot);
                    if (i >= j)
                        break;
                    notes.swap(i, j);
                }
                notes.swap(i, hi - 1);

                if (i - lo < hi - i)
                {
                    stack.push(i + 1);
                    stack.push(hi);
                    hi = i - 1;
                }
                else
                {
                    stack.push(lo);
                    stack.push(i - 1);
                    lo = i + 1;
                }
            }
        }
    }

    function insertionSort(lo:Int, hi:Int):Void
    {
        var pos = notes.positions;
        var i = lo + 1;
        while (i <= hi)
        {
            var j = i;
            while (j > lo && pos[j] < pos[j - 1])
            {
                notes.swap(j, j - 1);
                j--;
            }
            i++;
        }
    }

    function buildCharacters():Void
    {
        var oppCenterX = (lanesX[0] + lanesX[3]) / 2;
        var playerCenterX = (lanesX[4] + lanesX[7]) / 2;
        var charY = 220;

        dad = new Character(oppCenterX - DEST_SIZE / 2, charY, "dad", false);
        add(dad);

        bf = new Character(playerCenterX - DEST_SIZE / 2, charY, "bf", true);
        add(bf);
    }

    function buildStrums():Void
    {
        for (i in 0...8)
        {
            var s = new FlxSprite();
            s.loadGraphic("assets/images/arrow.png");
            s.setGraphicSize(DEST_SIZE_INT, DEST_SIZE_INT);
            s.updateHitbox();
            s.setPosition(lanesX[i], STRUM_Y);
            s.angle = angles[i % 4];
            add(s);
        }
    }

    function buildNotePool():Void
    {
        buildNoteAtlas();

        noteTilemap = new Tilemap(1280, 720, noteTileset, false);
        FlxG.addChildBelowMouse(noteTilemap);
    }

    function buildNoteAtlas():Void
    {
        var bitmaps = new Array<BitmapData>();
        var tileW = 0;
        var tileH = 0;
        for (p in noteGraphicPaths)
        {
            var bmp = Assets.getBitmapData(p);
            if (bmp == null)
                throw 'missing note graphic: $p';
            bitmaps.push(bmp);
            if (bmp.width > tileW)
                tileW = bmp.width;
            if (bmp.height > tileH)
                tileH = bmp.height;
        }

        var combined = new BitmapData(tileW * bitmaps.length, tileH, true, 0x00000000);
        for (i in 0...bitmaps.length)
            combined.copyPixels(bitmaps[i], bitmaps[i].rect, new Point(i * tileW, 0));

        var rects = new Array<Rectangle>();
        for (i in 0...bitmaps.length)
            rects.push(new Rectangle(i * tileW, 0, tileW, tileH));

        noteTileScale = DEST_SIZE / tileW;

        noteTileset = new Tileset(combined, rects);
    }

    function initEntryRing():Void
    {
        entryTiles = new Vector<Tile>(ENTRY_RING_START);
        entryPos = new Vector<Int>(ENTRY_RING_START);
        entryMask = ENTRY_RING_START - 1;
        entryHead = 0;
        entryTail = 0;
    }

    function growEntryRing():Void
    {
        var oldMask = entryMask;
        var newCap = (oldMask + 1) * 2;
        var newMask = newCap - 1;
        var newTiles = new Vector<Tile>(newCap);
        var newPos = new Vector<Int>(newCap);

        for (k in entryHead...entryTail)
        {
            newTiles[k & newMask] = entryTiles[k & oldMask];
            newPos[k & newMask] = entryPos[k & oldMask];
        }

        entryTiles = newTiles;
        entryPos = newPos;
        entryMask = newMask;
    }

    inline function acquireTile():Tile
    {
        if (freeTiles.length > 0)
            return freeTiles.pop();

        var tile = new Tile(0, -9999, -9999);
        tile.scaleX = noteTileScale;
        tile.scaleY = noteTileScale;
        return tile;
    }

    function buildOverlay():Void
    {
        var hudPanelTop = new FlxSprite(0, 0);
        hudPanelTop.makeGraphic(1280, 46, 0xAA000000);
        add(hudPanelTop);

        var hudPanelBottom = new FlxSprite(0, 690);
        hudPanelBottom.makeGraphic(1280, 30, 0xAA000000);
        add(hudPanelBottom);

        renderedText = new FlxText(8, 4, 260, "");
        renderedText.color = FlxColor.CYAN;
        renderedText.size = 12;
        add(renderedText);

        fpsText = new FlxText(8, 18, 260, "");
        fpsText.color = FlxColor.LIME;
        fpsText.size = 12;
        add(fpsText);

        memText = new FlxText(8, 32, 260, "");
        memText.color = FlxColor.YELLOW;
        memText.size = 12;
        add(memText);

        frameTimeText = new FlxText(8, 46, 260, "");
        frameTimeText.color = FlxColor.ORANGE;
        frameTimeText.size = 12;
        add(frameTimeText);

        tileCountText = new FlxText(8, 60, 260, "");
        tileCountText.color = FlxColor.MAGENTA;
        tileCountText.size = 12;
        add(tileCountText);

        progressText = new FlxText(8, 696, 300, "");
        progressText.color = FlxColor.WHITE;
        progressText.size = 12;
        progressText.wordWrap = false;
        progressText.autoSize = true;
        add(progressText);

        clockText = new FlxText(1280 - 608, 696, 600, "");
        clockText.alignment = FlxTextAlign.RIGHT;
        clockText.color = 0xFFDDDDDD;
        clockText.size = 12;
        add(clockText);

        var oppCenterX = (lanesX[0] + lanesX[3]) / 2;
        var playerCenterX = (lanesX[4] + lanesX[7]) / 2;

        oppNpsText = new FlxText(oppCenterX - 90, 4, 180, "");
        oppNpsText.color = 0xFFFF5C5C;
        oppNpsText.size = 16;
        oppNpsText.alignment = FlxTextAlign.CENTER;
        add(oppNpsText);

        playerNpsText = new FlxText(playerCenterX - 90, 4, 180, "");
        playerNpsText.color = 0xFF5CE1FF;
        playerNpsText.size = 16;
        playerNpsText.alignment = FlxTextAlign.CENTER;
        add(playerNpsText);
    }

    inline function pad2(v:Int):String
    {
        return v < 10 ? "0" + v : "" + v;
    }

    function formatWall(ms:Float):String
    {
        return formatTime(ms) + "." + Std.int((Math.max(0, ms) % 1000) / 100);
    }

    function updateClock():Void
    {
        if (!Settings.showClock)
            return;

        var nowSec = Sys.time();
        var tick = Std.int(nowSec * 10);
        if (tick == lastClockTick)
            return;
        lastClockTick = tick;

        var d = Date.now();
        var off = -Std.int(d.getTimezoneOffset());
        var sign = off < 0 ? "-" : "+";
        var a = off < 0 ? -off : off;

        var local = d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
            + " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds())
            + " (UTC" + sign + pad2(Std.int(a / 60)) + ":" + pad2(a % 60) + ")";

        if (loadClockText != null)
            setTextIfChanged(loadClockText, "local time: " + local);

        if (clockText != null)
        {
            var s = "local time: " + local;
            if (playWallStart >= 0)
            {
                var end = playWallEnd >= 0 ? playWallEnd : nowSec;
                s += "   |   real time playing: " + formatWall((end - playWallStart) * 1000);
            }
            setTextIfChanged(clockText, s);
        }
    }

    function buildStartPrompt():Void
    {
        startPromptText = new FlxText(0, 340, 1280, "press enter to start\n(ESC: menu)");
        startPromptText.alignment = FlxTextAlign.CENTER;
        startPromptText.size = 32;
        startPromptText.color = FlxColor.WHITE;
        add(startPromptText);
    }

    function buildSlider():Void
    {
        speedText = new FlxText(SLIDER_X, SLIDER_Y - 18, 200, "");
        speedText.color = FlxColor.WHITE;
        add(speedText);

        var sliderTrack = new FlxSprite(SLIDER_X, SLIDER_Y);
        sliderTrack.makeGraphic(Std.int(SLIDER_WIDTH), Std.int(SLIDER_HEIGHT), FlxColor.BLACK);
        add(sliderTrack);

        sliderHandle = new FlxSprite();
        sliderHandle.makeGraphic(Std.int(HANDLE_WIDTH), Std.int(HANDLE_HEIGHT), FlxColor.WHITE);
        add(sliderHandle);

        updateSliderVisual();
    }

    inline function clampSpeed(v:Float):Float
    {
        if (v < SPEED_MIN)
            return SPEED_MIN;
        if (v > SPEED_MAX)
            return SPEED_MAX;
        return v;
    }

    function updateSliderVisual():Void
    {
        var t = (scrollSpeed - SPEED_MIN) / (SPEED_MAX - SPEED_MIN);
        var handleX = SLIDER_X + t * SLIDER_WIDTH - HANDLE_WIDTH / 2;
        var handleY = SLIDER_Y + SLIDER_HEIGHT / 2 - HANDLE_HEIGHT / 2;
        sliderHandle.setPosition(handleX, handleY);

        var rounded = Math.round(scrollSpeed * 10) / 10;
        setTextIfChanged(speedText, 'Speed: $rounded');
    }

    function updateSlider():Void
    {
        var mouseX = FlxG.mouse.x;
        var mouseY = FlxG.mouse.y;

        var overHandle = mouseX >= sliderHandle.x && mouseX <= sliderHandle.x + HANDLE_WIDTH
            && mouseY >= sliderHandle.y && mouseY <= sliderHandle.y + HANDLE_HEIGHT;
        var overTrack = mouseX >= SLIDER_X && mouseX <= SLIDER_X + SLIDER_WIDTH
            && mouseY >= SLIDER_Y - 10 && mouseY <= SLIDER_Y + SLIDER_HEIGHT + 10;

        if (FlxG.mouse.justPressed && (overHandle || overTrack))
            draggingSlider = true;

        if (FlxG.mouse.justReleased)
            draggingSlider = false;

        if (draggingSlider)
        {
            var t = (mouseX - SLIDER_X) / SLIDER_WIDTH;
            if (t < 0)
                t = 0;
            if (t > 1)
                t = 1;
            scrollSpeed = SPEED_MIN + t * (SPEED_MAX - SPEED_MIN);
            updateSliderVisual();
        }
    }

    inline function syncVoices():Void
    {
        if (voices.length == 0 || music == null || !music.playing)
            return;

        var masterTime:Float = music.time;

        if (masterTime <= 0)
            return;

        for (v in voices)
        {
            var voiceTime:Float = v.time;

            if (voiceTime < 0)
                continue;

            if (Math.abs(voiceTime - masterTime) > SYNC_THRESHOLD_MS)
                v.time = masterTime;
        }
    }

    override public function update(elapsed:Float):Void
    {
        if (FlxG.keys.justPressed.ESCAPE)
        {
            leaveToMenu();
            return;
        }

        updateClock();

        if (loading)
        {
            updateLoading(elapsed);
            super.update(elapsed);
            return;
        }

        if (songEnded)
        {
            if (!endShown)
                showSongEnd();

            if (FlxG.keys.justPressed.ENTER)
            {
                leaveToMenu();
                return;
            }

            super.update(elapsed);
            return;
        }

        updateSlider();

        if (waitingToStart)
        {
            if (FlxG.keys.justPressed.ENTER)
            {
                waitingToStart = false;
                startPromptText.visible = false;
                beginCountdown();
            }
            else
            {
                super.update(elapsed);
                return;
            }
        }

        if (countingDown)
        {
            countdownMs -= elapsed * 1000;
            if (countdownMs <= 0)
                startPlayback();
            else
                updateCountdownText();
        }

        var now:Float;
        if (countingDown)
        {
            now = -countdownMs;
        }
        else
        {
            syncVoices();

            var audioPositionMs:Null<Float> = (music.playing && music.time >= 0) ? music.time : null;
            now = Conductor.update(audioPositionMs, elapsed);
        }

        var nowShift = STRUM_Y - now * scrollSpeed;

        advanceNoteWindows(nowShift);
        updateTimeBar(now);

        if (Settings.showStats)
        {
            var thisFrameMs = elapsed * 1000;
            frameTimeMs = thisFrameMs;
            if (thisFrameMs > maxFrameTimeMs)
                maxFrameTimeMs = thisFrameMs;

            hudElapsed += elapsed;
            hudFrames++;
            if (hudElapsed >= HUD_REFRESH_SEC)
            {
                var fpsDisplay = Math.round(hudFrames / hudElapsed);
                fpsText.text = 'FPS: $fpsDisplay';
                memText.text = 'Mem: ${formatBytes(System.totalMemoryNumber)}';

                var frameMsRounded = Math.round(frameTimeMs * 10) / 10;
                var maxFrameMsRounded = Math.round(maxFrameTimeMs * 10) / 10;
                frameTimeText.text = 'Frame: ${frameMsRounded}ms (max ${maxFrameMsRounded}ms)';

                hudElapsed = 0;
                hudFrames = 0;
                maxFrameTimeMs = 0;
            }
        }

        npsBucketElapsed += elapsed;
        if (npsBucketElapsed >= 1.0)
        {
            oppNpsPrevBucket = oppNpsBucket.toFloat();
            oppNpsBucket.set(0, 0);
            playerNpsPrevBucket = playerNpsBucket.toFloat();
            playerNpsBucket.set(0, 0);
            npsBucketElapsed -= Math.ffloor(npsBucketElapsed);
        }
        var t = npsBucketElapsed;
        oppNpsDisplay = Math.fround(oppNpsPrevBucket * (1 - t) + oppNpsBucket.toFloat());
        playerNpsDisplay = Math.fround(playerNpsPrevBucket * (1 - t) + playerNpsBucket.toFloat());

        var tileCount = refreshVisibleY(nowShift);
        visibleNotesNow.setDiff(scannedNotes, hitNotes);

        if (Settings.showStats)
        {
            if (tileCount != lastTileCountShown)
            {
                tileCountText.text = 'Tiles: $tileCount';
                lastTileCountShown = tileCount;
            }

            if (!visibleNotesNow.equals(lastVisibleNotes))
            {
                renderedText.text = 'Rendered Notes: ${visibleNotesNow.toDisplayString()}';
                lastVisibleNotes.copyFrom(visibleNotesNow);
            }
        }

        if (!hitNotes.equals(lastHitNotes))
        {
            progressText.text = '${hitNotes.toGroupedString()}/${totalNotes.toGroupedString()} (${CompactNumberFormatter.formatCompactNumber(hitNotes.toFloat())}/${CompactNumberFormatter.formatCompactNumber(totalNotes.toFloat())})';
            lastHitNotes.copyFrom(hitNotes);
        }

        if (oppNpsDisplay != lastOppNpsDisplay)
        {
            oppNpsText.text = 'Opp\n${npsString(oppNpsDisplay)} NPS';
            lastOppNpsDisplay = oppNpsDisplay;
        }

        if (playerNpsDisplay != lastPlayerNpsDisplay)
        {
            playerNpsText.text = 'Player\n${npsString(playerNpsDisplay)} NPS';
            lastPlayerNpsDisplay = playerNpsDisplay;
        }

        super.update(elapsed);
    }

    function advanceNoteWindows(nowShift:Float):Void
    {
        var n = notes.length;
        var pos = notes.positions;
        var lanes = notes.lanes;
        var speed = scrollSpeed;

        var hitLimit = (STRUM_Y - nowShift) / speed;
        var cullLimit = (NOTE_BOTTOM_CULL - nowShift) / speed;

        var oppHits = frameOppHits;
        var playerHits = framePlayerHits;
        oppHits.set(0, 0);
        playerHits.set(0, 0);
        var lastOppDir = -1;
        var lastPlayerDir = -1;
        while (notesHead < n && pos[notesHead] < hitLimit)
        {
            var lo = notes.countLo(notesHead);
            var hi = notes.countHi(notesHead);

            if (lo != 0 || hi != 0)
            {
                var lane = lanes.get(notesHead);
                if (lane >= 4)
                {
                    playerHits.addParts(hi, lo);
                    lastPlayerDir = lane - 4;
                }
                else
                {
                    oppHits.addParts(hi, lo);
                    lastOppDir = lane;
                }
                hitNotes.addParts(hi, lo);
            }
            notesHead++;
        }

        if (lastOppDir >= 0)
        {
            dad.sing(laneDirs[lastOppDir]);
            oppNpsBucket.addU64(oppHits);
        }
        if (lastPlayerDir >= 0)
        {
            bf.sing(laneDirs[lastPlayerDir]);
            playerNpsBucket.addU64(playerHits);
        }

        var removed = 0;
        while (entryHead < entryTail && entryPos[entryHead & entryMask] < hitLimit)
        {
            var slot = entryHead & entryMask;
            freeTiles.push(entryTiles[slot]);
            entryTiles[slot] = null;
            entryHead++;
            removed++;
        }
        if (removed > 0)
            noteTilemap.removeTiles(0, removed - 1);

        enteringScratch.resize(0);
        while (visibleEnd < n)
        {
            var p = pos[visibleEnd];
            if (p > cullLimit)
                break;

            var lo = notes.countLo(visibleEnd);
            var hi = notes.countHi(visibleEnd);
            scannedNotes.addParts(hi, lo);

            if (p >= hitLimit && (lo != 0 || hi != 0))
            {
                if (!runValid || p != runPos)
                {
                    runValid = true;
                    runPos = p;
                    runMask = 0;
                }

                var lane = lanes.get(visibleEnd);
                var bit = 1 << lane;
                if ((runMask & bit) == 0)
                {
                    runMask |= bit;

                    var tile = acquireTile();
                    tile.x = lanesX[lane];
                    tile.id = lane % 4;

                    if (entryTail - entryHead > entryMask)
                        growEntryRing();

                    var slot = entryTail & entryMask;
                    entryTiles[slot] = tile;
                    entryPos[slot] = p;
                    entryTail++;

                    enteringScratch.push(tile);
                }
            }

            visibleEnd++;
        }

        if (enteringScratch.length > 0)
            noteTilemap.addTiles(enteringScratch);
    }

    function refreshVisibleY(nowShift:Float):Int
    {
        var speed = scrollSpeed;
        var mask = entryMask;
        var tiles = entryTiles;
        var times = entryPos;

        for (k in entryHead...entryTail)
            tiles[k & mask].y = times[k & mask] * speed + nowShift;

        return entryTail - entryHead;
    }

    override public function destroy():Void
    {
        workerMutex.acquire();
        workerCancelled = true;
        workerMutex.release();

        if (noteTilemap != null && noteTilemap.parent != null)
            noteTilemap.parent.removeChild(noteTilemap);

        if (noteTileset != null && noteTileset.bitmapData != null)
            noteTileset.bitmapData.dispose();

        super.destroy();
    }
}
