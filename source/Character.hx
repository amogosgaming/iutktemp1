package;

import flixel.FlxSprite;
import flixel.graphics.frames.FlxAtlasFrames;

class Character extends FlxSprite
{
    static inline var SING_HOLD_MS:Float = 500;
    static inline var ANIM_FPS:Int = 24;
    static inline var SPRITE_SCALE:Float = 0.6;

    public var isPlayer:Bool = false;
    public var animOffsets:Map<String, Array<Float>> = new Map();

    var baseX:Float;
    var baseY:Float;

    var holdTimer:Float = 0;

    public function new(x:Float, y:Float, charName:String, isPlayer:Bool = false)
    {
        super(x, y);
        baseX = x;
        baseY = y;
        this.isPlayer = isPlayer;

        switch (charName)
        {
            case "dad", "DADDY_DEAREST":
                loadDaddyDearest();
            case "bf", "BOYFRIEND":
                loadBoyfriend();
            default:
                trace('Character.hx: unknown character "$charName"');
        }

        playAnim("idle", true);
    }

    function loadDaddyDearest():Void
    {
        frames = FlxAtlasFrames.fromSparrow("assets/images/DADDY_DEAREST.png", "assets/images/DADDY_DEAREST.xml");

        defineAnim("idle", "Dad idle dance", true);
        defineAnim("singLEFT", "Dad Sing Note LEFT");
        defineAnim("singDOWN", "Dad Sing Note DOWN");
        defineAnim("singUP", "Dad Sing Note UP");
        defineAnim("singRIGHT", "Dad Sing Note RIGHT");

        applySpriteScale();
    }

    function loadBoyfriend():Void
    {
        frames = FlxAtlasFrames.fromSparrow("assets/images/BOYFRIEND.png", "assets/images/BOYFRIEND.xml");

        defineAnim("idle", "BF idle dance", true);
        defineAnim("idleShaking", "BF idle shaking", true);
        defineAnim("singLEFT", "BF NOTE LEFT0");
        defineAnim("singDOWN", "BF NOTE DOWN0");
        defineAnim("singUP", "BF NOTE UP0");
        defineAnim("singRIGHT", "BF NOTE RIGHT0");
        defineAnim("singLEFTmiss", "BF NOTE LEFT MISS");
        defineAnim("singDOWNmiss", "BF NOTE DOWN MISS");
        defineAnim("singUPmiss", "BF NOTE UP MISS");
        defineAnim("singRIGHTmiss", "BF NOTE RIGHT MISS");
        defineAnim("hey", "BF HEY!!");
        defineAnim("hit", "BF hit");
        defineAnim("preAttack", "bf pre attack");
        defineAnim("attack", "boyfriend attack");
        defineAnim("dodge", "boyfriend dodge");

        applySpriteScale();
    }

    function defineAnim(name:String, prefix:String, looped:Bool = false):Void
    {
        animation.addByPrefix(name, prefix, ANIM_FPS, looped);
        addOffset(name, 0, 0);
    }

    function applySpriteScale():Void
    {
        scale.set(SPRITE_SCALE, SPRITE_SCALE);
        updateHitbox();
    }

    public function addOffset(name:String, x:Float = 0, y:Float = 0):Void
    {
        animOffsets[name] = [x, y];
    }

    public function playAnim(name:String, force:Bool = false):Void
    {
        var animOffset = animOffsets[name];
        if (animOffset == null || !animation.exists(name))
            return;

        animation.play(name, force);

        x = baseX + animOffset[0];
        y = baseY + animOffset[1];
    }

    public function sing(direction:String, miss:Bool = false):Void
    {
        var animName = "sing" + direction + (miss ? "miss" : "");
        if (!animOffsets.exists(animName))
            return;

        playAnim(animName, true);
        holdTimer = SING_HOLD_MS;
    }

    override public function update(elapsed:Float):Void
    {
        super.update(elapsed);

        if (holdTimer > 0)
        {
            holdTimer -= elapsed * 1000;
            if (holdTimer <= 0)
                playAnim("idle");
        }
    }
}
