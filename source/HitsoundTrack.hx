package;

import flixel.FlxG;
import flixel.sound.FlxSound;
import haxe.ds.IntMap;
import haxe.ds.Vector;
import haxe.io.Bytes;
import lime.media.AudioBuffer;
import lime.utils.UInt8Array;
import openfl.media.Sound;
import sys.FileSystem;

private class Grain
{
    public var data:Vector<Float>;
    public var length:Int;
    public var overlapLength:Float;
    public var energy:Float;

    public function new(data:Vector<Float>, length:Int, overlapLength:Float, energy:Float)
    {
        this.data = data;
        this.length = length;
        this.overlapLength = overlapLength;
        this.energy = energy;
    }

    public inline function at(x:Float):Float
    {
        var m = Std.int(x);
        var f = x - m;
        var y0 = data[m];
        var y1 = data[m + 1];
        var y2 = data[m + 2];
        var y3 = data[m + 3];
        return y1 + 0.5 * f * (y2 - y0 + f * (2 * y0 - 5 * y1 + 4 * y2 - y3 + f * (3 * (y1 - y2) + y3 - y0)));
    }
}

private class HitGroup
{
    public var position:Int = 0;
    public var count:Float = 0;
    public var next:Int = 0;

    public function new() {}
}

class HitsoundTrack
{
    public static inline var RATE:Int = 48000;
    public static inline var MIN_LANE:Int = 4;
    public static inline var MAX_SAMPLES:Int = 500000000;
    public static inline var FILE_NAME:String = "hitsound.ogg";

    static inline var SILENCE_THRESHOLD:Float = 0.02;
    static inline var DEFAULT_FREQ:Float = 1500;
    static inline var DEFAULT_MS:Float = 30;
    static inline var DEFAULT_DECAY_MS:Float = 6;

    static inline var DEFAULT_STEP_MS:Int = 30;
    static inline var MAX_STEP_MS:Int = 1000;
    static inline var BLOCK:Int = 64;
    static inline var OVERSAMPLE:Int = 4;
    static inline var DENSE_RATIO:Float = 8;
    static inline var MIN_PERIOD:Float = 3;
    static inline var TRIM_ENERGY:Float = 0.9999;
    static inline var BODY_ENERGY:Float = 0.99;
    static inline var HEAD_SAMPLES:Int = 8;
    static inline var TAIL_SAMPLES:Int = 96;
    static inline var MAX_BOOST:Float = 10;
    static inline var KNEE:Float = 0.8;
    static inline var TWO_32:Float = 4294967296.0;
    static inline var MAX_CYCLE_CACHE_FLOATS:Int = 8000000;

    public static function build(notes:NoteBuffer, songLengthMs:Float, volume:Float):FlxSound
    {
        if (notes == null || notes.length == 0 || volume <= 0)
            return null;

        var lengthMs = songLengthMs;
        if (lengthMs <= 0)
            lengthMs = notes.positions[notes.length - 1] - Conductor.offset + 1000;

        var totalF = Math.ceil(lengthMs * RATE / 1000);
        if (totalF < 1 || totalF > MAX_SAMPLES)
        {
            trace('HitsoundTrack: song too long to render ($lengthMs ms)');
            return null;
        }

        var start = Sys.time();
        var bytes:Bytes = null;

        try
        {
            var grain = prepareGrain(loadSample());
            bytes = render(notes, grain, Std.int(totalF), Conductor.offset, volume > 1 ? 1.0 : volume);
        }
        catch (e:Dynamic)
        {
            trace('HitsoundTrack: rendering failed ($e), continuing without hitsounds');
            return null;
        }

        var buffer = new AudioBuffer();
        buffer.bitsPerSample = 16;
        buffer.channels = 1;
        buffer.sampleRate = RATE;
        buffer.data = UInt8Array.fromBytes(bytes);

        trace('HitsoundTrack: rendered ${Std.int(totalF)} samples in ${(Sys.time() - start) * 1000} ms');
        return FlxG.sound.load(Sound.fromAudioBuffer(buffer), 1, false);
    }

    static function render(notes:NoteBuffer, grain:Grain, total:Int, offsetMs:Float, volume:Float):Bytes
    {
        var scale = RATE / 1000.0;
        var stepMs = detectStep(notes);
        var blocks = Std.int(total / BLOCK) + 3;

        var density = new Vector<Float>(blocks);
        for (b in 0...blocks)
            density[b] = 0;

        var cur = new HitGroup();
        var nxt = new HitGroup();
        var has = nextGroup(notes, 0, cur);
        while (has)
        {
            var has2 = nextGroup(notes, cur.next, nxt);
            var spanMs = has2 && nxt.position - cur.position < stepMs ? nxt.position - cur.position : stepMs;

            var s0 = (cur.position - offsetMs) * scale;
            if (s0 >= total)
                break;

            if (s0 >= -0.5)
            {
                if (s0 < 0)
                    s0 = 0;
                var span = spanMs * scale;
                var maxCount = span / MIN_PERIOD;
                spreadDensity(density, blocks, s0, span, cur.count > maxCount ? maxCount : cur.count);
            }

            var t = cur;
            cur = nxt;
            nxt = t;
            has = has2;
        }

        var gain = blockGains(density, blocks, grain.overlapLength);

        var acc = Bytes.alloc(total * 4);
        acc.fill(0, total * 4, 0);

        var cycles = new IntMap<Vector<Float>>();
        var cycleFloats = 0;

        cur = new HitGroup();
        nxt = new HitGroup();
        has = nextGroup(notes, 0, cur);
        while (has)
        {
            var has2 = nextGroup(notes, cur.next, nxt);
            var spanMs = has2 && nxt.position - cur.position < stepMs ? nxt.position - cur.position : stepMs;

            var s0 = (cur.position - offsetMs) * scale;
            if (s0 >= total)
                break;

            if (s0 >= -0.5)
            {
                if (s0 < 0)
                    s0 = 0;

                var span = spanMs * scale;
                var maxCount = span / MIN_PERIOD;
                var count = cur.count;
                var clamped = count > maxCount;
                if (clamped)
                    count = maxCount;

                var period = span / count;
                var dense = clamped || period < MIN_PERIOD || count * grain.length > DENSE_RATIO * span;

                if (!dense)
                {
                    var hits = Std.int(count + 0.5);
                    for (j in 0...hits)
                        addGrain(acc, grain, s0 + j * period, total);
                }
                else
                {
                    var key = spanMs * 65536 + (clamped ? 65535 : Std.int(count + 0.5));
                    var cycle = cycles.get(key);
                    if (cycle == null)
                    {
                        cycle = buildCycle(grain, period);
                        if (cycleFloats + cycle.length > MAX_CYCLE_CACHE_FLOATS)
                        {
                            cycles = new IntMap<Vector<Float>>();
                            cycleFloats = 0;
                        }
                        cycles.set(key, cycle);
                        cycleFloats += cycle.length;
                    }

                    var fadeLen = Std.int(Math.min(grain.length, span) * 0.5);
                    if (fadeLen < 16)
                        fadeLen = 16;
                    if (fadeLen > span * 0.5)
                        fadeLen = Std.int(span * 0.5);
                    if (fadeLen < 1)
                        fadeLen = 1;

                    addDense(acc, cycle, period, s0, span, fadeLen, total);
                }
            }

            var t = cur;
            cur = nxt;
            nxt = t;
            has = has2;
        }

        for (n in 0...total)
        {
            var pos = (n + 0.5) / BLOCK - 0.5;
            if (pos < 0)
                pos = 0;
            var b = Std.int(pos);
            var f = pos - b;
            var g = gain[b] + (gain[b + 1] - gain[b]) * f;

            var v = softClip(acc.getFloat(n << 2) * g * volume);
            var q = Math.round(v * 32767);
            if (q > 32767)
                q = 32767;
            else if (q < -32768)
                q = -32768;

            var p = n << 1;
            acc.set(p, q & 0xFF);
            acc.set(p + 1, (q >> 8) & 0xFF);
        }

        return acc.sub(0, total * 2);
    }

    static function detectStep(notes:NoteBuffer):Int
    {
        var histogram = new Vector<Int>(MAX_STEP_MS + 1);
        for (i in 0...MAX_STEP_MS + 1)
            histogram[i] = 0;

        var cur = new HitGroup();
        var nxt = new HitGroup();
        var has = nextGroup(notes, 0, cur);
        while (has)
        {
            var has2 = nextGroup(notes, cur.next, nxt);
            if (has2)
            {
                var gap = nxt.position - cur.position;
                if (gap > 0 && gap <= MAX_STEP_MS)
                    histogram[gap]++;
            }
            var t = cur;
            cur = nxt;
            nxt = t;
            has = has2;
        }

        var best = DEFAULT_STEP_MS;
        var bestCount = 0;
        for (g in 1...MAX_STEP_MS + 1)
        {
            if (histogram[g] > bestCount)
            {
                bestCount = histogram[g];
                best = g;
            }
        }
        return best;
    }

    static function nextGroup(notes:NoteBuffer, from:Int, group:HitGroup):Bool
    {
        var n = notes.length;
        var pos = notes.positions;
        var lanes = notes.lanes;

        var i = from;
        var found = false;
        var sum = 0.0;
        var at = 0;

        while (i < n)
        {
            if (lanes.get(i) < MIN_LANE)
            {
                i++;
                continue;
            }

            var lo = notes.countLo(i);
            var hi = notes.countHi(i);
            if (lo == 0 && hi == 0)
            {
                i++;
                continue;
            }

            if (!found)
            {
                found = true;
                at = pos[i];
            }
            else if (pos[i] != at)
            {
                break;
            }

            sum += (hi < 0 ? hi + TWO_32 : hi + 0.0) * TWO_32 + (lo < 0 ? lo + TWO_32 : lo + 0.0);
            i++;
        }

        if (!found)
            return false;

        group.position = at;
        group.count = sum;
        group.next = i;
        return true;
    }

    static function spreadDensity(density:Vector<Float>, blocks:Int, s0:Float, span:Float, count:Float):Void
    {
        var b = Std.int(s0 / BLOCK);
        if (count <= 1)
        {
            if (b < blocks)
                density[b] += count;
            return;
        }

        var end = s0 + span;
        var rate = count / span;
        while (b < blocks)
        {
            var bs = b * BLOCK;
            var be = bs + BLOCK;
            var lo = bs > s0 ? bs : s0;
            var hi = be < end ? be : end;
            if (hi > lo)
                density[b] += rate * (hi - lo);
            if (be >= end)
                break;
            b++;
        }
    }

    static function blockGains(density:Vector<Float>, blocks:Int, overlapLength:Float):Vector<Float>
    {
        var half = Std.int(Math.ceil((overlapLength / BLOCK - 1) / 2));
        if (half < 0)
            half = 0;
        var window = (2 * half + 1) * BLOCK;
        var norm = overlapLength / window;

        var prefix = new Vector<Float>(blocks + 1);
        prefix[0] = 0;
        for (b in 0...blocks)
            prefix[b + 1] = prefix[b] + density[b];

        var gain = new Vector<Float>(blocks);
        for (b in 0...blocks)
        {
            var lo = b - half;
            var hi = b + half + 1;
            if (lo < 0)
                lo = 0;
            if (hi > blocks)
                hi = blocks;
            var overlap = (prefix[hi] - prefix[lo]) * norm;
            gain[b] = overlap > 1 ? 1 / Math.sqrt(overlap) : 1;
        }
        return gain;
    }

    static function addGrain(acc:Bytes, grain:Grain, t:Float, total:Int):Void
    {
        var start = Std.int(Math.ceil(t));
        if (start >= total)
            return;

        var f = start - t;
        var end = start + grain.length;
        if (end > total)
            end = total;

        var p = start << 2;
        var x = f;
        for (n in start...end)
        {
            acc.setFloat(p, acc.getFloat(p) + grain.at(x));
            x += 1;
            p += 4;
        }
    }

    static function buildCycle(grain:Grain, period:Float):Vector<Float>
    {
        var m = Std.int(Math.ceil(period * OVERSAMPLE));
        var table = new Vector<Float>(m + 1);
        for (i in 0...m)
        {
            var x = period * i / m;
            var sum = 0.0;
            while (x < grain.length)
            {
                sum += grain.at(x);
                x += period;
            }
            table[i] = sum;
        }

        var power = 0.0;
        for (i in 0...m)
            power += table[i] * table[i];
        var rms = Math.sqrt(power / m);

        if (rms > 1e-9)
        {
            var boost = Math.sqrt(grain.energy / period) / rms;
            if (boost > MAX_BOOST)
                boost = MAX_BOOST;
            for (i in 0...m)
                table[i] *= boost;
        }

        table[m] = table[0];
        return table;
    }

    static function addDense(acc:Bytes, table:Vector<Float>, period:Float, t0:Float, span:Float, fadeLen:Int, total:Int):Void
    {
        var start = Std.int(Math.ceil(t0));
        var end = Std.int(Math.ceil(t0 + span)) + fadeLen;
        if (end > total)
            end = total;

        var m = table.length - 1;
        var inv = 1 / period;
        var p = start << 2;

        for (n in start...end)
        {
            var tau = n - t0;
            var ph = tau * inv;
            ph -= Math.floor(ph);
            var idx = ph * m;
            var i = Std.int(idx);
            if (i >= m)
                i = m - 1;
            var fr = idx - i;
            var v = table[i] + (table[i + 1] - table[i]) * fr;

            if (tau < fadeLen)
                v *= 0.5 - 0.5 * Math.cos(Math.PI * tau / fadeLen);
            else if (tau >= span)
                v *= 0.5 + 0.5 * Math.cos(Math.PI * (tau - span) / fadeLen);

            acc.setFloat(p, acc.getFloat(p) + v);
            p += 4;
        }
    }

    static inline function softClip(x:Float):Float
    {
        var a = x < 0 ? -x : x;
        if (a <= KNEE)
            return x;
        var t = (a - KNEE) / (1 - KNEE);
        var y = KNEE + (1 - KNEE) * t / (1 + t);
        return x < 0 ? -y : y;
    }

    static function prepareGrain(raw:Array<Float>):Grain
    {
        var total = 0.0;
        for (v in raw)
            total += v * v;

        var trim = raw.length;
        var body = raw.length;
        if (total > 0)
        {
            var run = 0.0;
            var trimFound = false;
            var bodyFound = false;
            for (i in 0...raw.length)
            {
                run += raw[i] * raw[i];
                if (!bodyFound && run >= total * BODY_ENERGY)
                {
                    body = i + 1;
                    bodyFound = true;
                }
                if (!trimFound && run >= total * TRIM_ENERGY)
                {
                    trim = i + 1;
                    trimFound = true;
                    break;
                }
            }
        }

        var length = trim < 4 ? (raw.length < 4 ? raw.length : 4) : trim;
        if (length < 1)
            length = 1;

        var data = new Vector<Float>(length + 3);
        for (i in 0...length + 3)
            data[i] = 0;

        var head = HEAD_SAMPLES < length >> 1 ? HEAD_SAMPLES : length >> 1;
        var tail = TAIL_SAMPLES < length >> 2 ? TAIL_SAMPLES : length >> 2;
        if (tail < 1)
            tail = 1;

        var energy = 0.0;
        for (i in 0...length)
        {
            var w = 1.0;
            if (i < head)
                w = 0.5 - 0.5 * Math.cos(Math.PI * (i + 1) / (head + 1));
            var k = i - (length - tail);
            if (k >= 0)
                w *= 0.5 + 0.5 * Math.cos(Math.PI * (k + 1) / (tail + 1));
            data[i + 1] = raw[i] * w;
            energy += data[i + 1] * data[i + 1];
        }

        return new Grain(data, length, body < 1 ? 1 : (body > length ? length : body), energy);
    }

    static function loadSample():Array<Float>
    {
        var path = PlayState.AUDIO_DIR + "/" + FILE_NAME;
        if (FileSystem.exists(path))
        {
            try
            {
                var decoded = decodeFile(path);
                if (decoded != null && decoded.length > 0)
                    return decoded;
                trace('HitsoundTrack: unsupported $path, using the built-in hitsound');
            }
            catch (e:Dynamic)
            {
                trace('HitsoundTrack: failed to read $path ($e), using the built-in hitsound');
            }
        }
        return defaultSample();
    }

    static function defaultSample():Array<Float>
    {
        var n = Std.int(DEFAULT_MS * RATE / 1000);
        var out = new Array<Float>();
        for (i in 0...n)
        {
            var t = i / RATE;
            out.push(Math.cos(2 * Math.PI * DEFAULT_FREQ * t) * Math.exp(-t * 1000 / DEFAULT_DECAY_MS));
        }
        return out;
    }

    static function decodeFile(path:String):Array<Float>
    {
        var sound:Sound = Sound.fromFile(path);
        var buffer:AudioBuffer = sound == null ? null : @:privateAccess sound.__buffer;
        if (buffer == null || buffer.data == null || buffer.bitsPerSample != 16 || buffer.channels < 1)
            return null;

        var ch = buffer.channels;
        var raw = buffer.data;
        var frames = Std.int(raw.length / (2 * ch));

        var mono = new Array<Float>();
        var started = false;
        for (f in 0...frames)
        {
            var sum = 0.0;
            for (c in 0...ch)
            {
                var p = (f * ch + c) * 2;
                var v = raw[p] | (raw[p + 1] << 8);
                if (v >= 32768)
                    v -= 65536;
                sum += v / 32768;
            }

            var s = sum / ch;
            if (!started && Math.abs(s) > SILENCE_THRESHOLD)
                started = true;
            if (started)
                mono.push(s);
        }

        return resample(mono, buffer.sampleRate);
    }

    static function resample(src:Array<Float>, srcRate:Int):Array<Float>
    {
        if (srcRate == RATE || src.length < 2 || srcRate <= 0)
            return src;

        var ratio = srcRate / RATE;
        var n = Std.int(src.length / ratio);
        var out = new Array<Float>();
        for (i in 0...n)
        {
            var x = i * ratio;
            var i0 = Std.int(x);
            var i1 = i0 + 1 < src.length ? i0 + 1 : i0;
            var f = x - i0;
            out.push(src[i0] * (1 - f) + src[i1] * f);
        }
        return out;
    }
}
