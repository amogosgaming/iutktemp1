package;

import haxe.ds.Vector;
import haxe.crypto.Crc32;
import haxe.io.Bytes;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileInput;
import sys.io.FileSeek;

class ChartBinary
{
    static inline var MAGIC:String = "FNC1";
    static inline var HEADER_V2:Int = 9;
    static inline var HEADER_V3:Int = 17;
    static inline var CELL_BYTES_V3:Int = 13;
    static inline var NOTE_BYTES_V2:Int = 5;
    static inline var LANES:Int = 8;

    static inline var CHUNK:Int = 1 << 18;

    public static function load(path:String, ?onProgress:Float->Void):NoteBuffer
    {
        var fileSize:Int = FileSystem.stat(path).size;

        if (fileSize < 0)
            throw 'chart binary is larger than 2 GB, which is not supported: $path';

        if (fileSize < 5)
            throw 'corrupt or truncated chart binary: file is only $fileSize bytes: $path';

        var input = File.read(path, true);
        var second:FileInput = null;
        var buffer:NoteBuffer = null;
        var failure:Dynamic = null;

        try
        {
            var head = Bytes.alloc(5);
            input.readFullBytes(head, 0, 5);

            if (head.getString(0, 4) != MAGIC)
                throw 'invalid chart binary: bad magic in $path';

            var version = head.get(4);

            if (version == 4)
            {
                buffer = loadV4(path, fileSize, onProgress);
            }
            else if (version == 3)
            {
                buffer = loadV3(input, fileSize, path, onProgress);
            }
            else if (version == 2)
            {
                second = File.read(path, true);
                buffer = loadV2(input, second, fileSize, path, onProgress);
            }
            else
            {
                throw 'unsupported chart binary version: $version';
            }
        }
        catch (e:Dynamic)
        {
            failure = e;
        }

        input.close();
        if (second != null)
            second.close();

        if (failure != null)
            throw failure;

        return buffer;
    }

    static function readU31(s:V4Stream, name:String, path:String):Int
    {
        s.varint();
        if (s.hi != 0 || s.lo < 0)
            throw 'corrupt chart binary: $name out of range in $path';
        return s.lo;
    }

    static function loadV4(path:String, fileSize:Int, ?onProgress:Float->Void):NoteBuffer
    {
        var header = new V4Stream(path, 5, fileSize - 5, false);

        var cellCount = 0;
        var groupCount = 0;
        var declared = new U64();
        var firstTime = 0.0;
        var lenD = 0;
        var lenM = 0;
        var lenC = 0;
        var crcD = 0;
        var crcM = 0;
        var crcC = 0;
        var bodyStart = 0;

        try
        {
            cellCount = readU31(header, 'cell count', path);
            groupCount = readU31(header, 'group count', path);
            header.varint();
            declared.set(header.hi, header.lo);
            header.varint();
            if (header.hi != 0)
                throw 'corrupt chart binary: first time out of range in $path';
            firstTime = V4Stream.unsigned(header.lo);
            lenD = readU31(header, 'stream length', path);
            lenM = readU31(header, 'stream length', path);
            lenC = readU31(header, 'stream length', path);
            crcD = header.fixed32();
            crcM = header.fixed32();
            crcC = header.fixed32();
            bodyStart = header.offset();
        }
        catch (e:Dynamic)
        {
            header.close();
            throw e;
        }
        header.close();

        var expectedSize:Float = bodyStart + 0.0 + lenD + lenM + lenC;
        if (expectedSize != fileSize)
            throw 'corrupt or truncated chart binary: streams need ${Std.int(expectedSize)} bytes but file is $fileSize bytes: $path';

        if (cellCount > NoteBuffer.MAX_SAFE_CELLS)
            throw 'chart binary rejected: $cellCount cells exceeds the safe allocation limit '
                + '(${NoteBuffer.MAX_SAFE_CELLS}) for this engine build: $path';

        if (groupCount > cellCount || (groupCount == 0) != (cellCount == 0) || cellCount > groupCount * LANES)
            throw 'corrupt chart binary: inconsistent cell and group counts in $path';

        var d = new V4Stream(path, bodyStart, lenD, false);
        var m = new V4Stream(path, bodyStart + lenD, lenM, true);
        var c = new V4Stream(path, bodyStart + lenD + lenM, lenC, false);
        var buffer:NoteBuffer = null;
        var failure:Dynamic = null;

        try
        {
            buffer = decodeV4(d, m, c, cellCount, groupCount, declared, firstTime, crcD, crcM, crcC, path, onProgress);
        }
        catch (e:Dynamic)
        {
            failure = e;
        }

        d.close();
        m.close();
        c.close();

        if (failure != null)
            throw failure;

        return buffer;
    }

    static function decodeV4(d:V4Stream, m:V4Stream, c:V4Stream, cellCount:Int, groupCount:Int, declared:U64,
        firstTime:Float, crcD:Int, crcM:Int, crcC:Int, path:String, ?onProgress:Float->Void):NoteBuffer
    {
        var buffer = new NoteBuffer(cellCount);
        var sum = new U64();
        var time = firstTime;
        var cells = 0;

        for (g in 0...groupCount)
        {
            if (g > 0)
            {
                d.item();
                if (d.hi != 0)
                    throw 'corrupt chart binary: time delta out of range in $path';
                time += V4Stream.unsigned(d.lo) + 1.0;
                if (time > 4294967295.0)
                    throw 'corrupt chart binary: time overflow in $path';
            }

            m.item();
            var mask = m.lo;
            if (mask < 1 || mask > 255)
                throw 'corrupt chart binary: invalid lane mask $mask in $path';

            var position = Std.int(time - 2147483648.0);

            for (lane in 0...LANES)
            {
                if (((mask >> lane) & 1) == 0)
                    continue;

                if (cells >= cellCount)
                    throw 'corrupt chart binary: more cells than declared in $path';

                c.item();
                if (c.hi == -1 && c.lo == -1)
                    throw 'chart binary rejected: cell count does not fit in 64 bits: $path';

                var lo = c.lo + 1;
                var hi = lo == 0 ? c.hi + 1 : c.hi;

                if (sum.addPartsChecked(hi, lo))
                    throw 'chart binary rejected: total note count does not fit in 64 bits: $path';

                buffer.pushCell(position, lane, lo, hi);
                cells++;
            }

            if (onProgress != null && (g & 0xFFFF) == 0)
                onProgress(g / groupCount);
        }

        if (cells != cellCount)
            throw 'corrupt chart binary: header says $cellCount cells but streams hold $cells: $path';

        if (!sum.equals(declared))
            throw 'corrupt chart binary: header says $declared notes but the cells add up to $sum: $path';

        d.finish(crcD);
        m.finish(crcM);
        c.finish(crcC);

        buffer.total.copyFrom(sum);
        if (onProgress != null)
            onProgress(1.0);
        return buffer;
    }

    static function loadV3(input:FileInput, fileSize:Int, path:String, ?onProgress:Float->Void):NoteBuffer
    {
        if (fileSize < HEADER_V3)
            throw 'corrupt or truncated chart binary: file is only $fileSize bytes: $path';

        var rest = Bytes.alloc(HEADER_V3 - 5);
        input.readFullBytes(rest, 0, rest.length);

        var cellCount = rest.getInt32(0);
        var totalLo = rest.getInt32(4);
        var totalHi = rest.getInt32(8);

        #if debug
        trace('binary chart v3: $cellCount cells, ${new U64(totalHi, totalLo)} notes');
        #end

        if (cellCount < 0)
            throw 'corrupt chart binary: negative cell count ($cellCount) in $path';

        var requiredBytes:Float = HEADER_V3 + cellCount * (CELL_BYTES_V3 + 0.0);

        if (requiredBytes > fileSize)
            throw 'corrupt or truncated chart binary: header claims $cellCount cells '
                + '(needs ${Std.int(requiredBytes)} bytes) but file is only $fileSize bytes: $path';

        if (cellCount > NoteBuffer.MAX_SAFE_CELLS)
            throw 'chart binary rejected: $cellCount cells exceeds the safe allocation limit '
                + '(${NoteBuffer.MAX_SAFE_CELLS}) for this engine build: $path';

        var buffer = new NoteBuffer(cellCount);
        var positions = buffer.positions;
        var lanes = buffer.lanes;
        var counts = buffer.counts;

        var chunk = Bytes.alloc(CHUNK * 4);
        var done = 0;
        while (done < cellCount)
        {
            var n = cellCount - done;
            if (n > CHUNK)
                n = CHUNK;

            input.readFullBytes(chunk, 0, n * 4);
            for (i in 0...n)
                positions[done + i] = chunk.getInt32(i * 4);

            done += n;
            if (onProgress != null)
                onProgress(done / cellCount * 4 / CELL_BYTES_V3);
        }

        done = 0;
        while (done < cellCount)
        {
            var n = cellCount - done;
            if (n > CHUNK * 4)
                n = CHUNK * 4;

            input.readFullBytes(lanes, done, n);
            for (i in done...done + n)
                if (lanes.get(i) >= LANES)
                    throw 'corrupt chart binary: lane ${lanes.get(i)} out of range (0-${LANES - 1}) in $path';

            done += n;
            if (onProgress != null)
                onProgress((4 + done / cellCount) / CELL_BYTES_V3);
        }

        var sum = new U64();
        done = 0;
        while (done < cellCount)
        {
            var n = cellCount - done;
            if (n > CHUNK)
                n = CHUNK;

            input.readFullBytes(counts, done * 8, n * 8);
            for (i in done...done + n)
            {
                if (sum.addPartsChecked(counts.getInt32(i * 8 + 4), counts.getInt32(i * 8)))
                    throw 'chart binary rejected: total note count does not fit in 64 bits: $path';
            }

            done += n;
            if (onProgress != null)
                onProgress((5 + done / cellCount * 8) / CELL_BYTES_V3);
        }

        var declared = new U64(totalHi, totalLo);
        if (!sum.equals(declared))
            throw 'corrupt chart binary: header says $declared notes but the cells add up to $sum: $path';

        buffer.setLength(cellCount);
        buffer.total.copyFrom(sum);
        return buffer;
    }

    static function loadV2(input:FileInput, lanesInput:FileInput, fileSize:Int, path:String, ?onProgress:Float->Void):NoteBuffer
    {
        if (fileSize < HEADER_V2)
            throw 'corrupt or truncated chart binary: file is only $fileSize bytes: $path';

        var rest = Bytes.alloc(4);
        input.readFullBytes(rest, 0, 4);
        var noteCount = rest.getInt32(0);

        #if debug
        trace('binary chart v2: $noteCount notes');
        #end

        if (noteCount < 0)
            throw 'corrupt chart binary: negative note count ($noteCount) in $path';

        var requiredBytes:Float = HEADER_V2 + noteCount * (NOTE_BYTES_V2 + 0.0);

        if (requiredBytes > fileSize)
            throw 'corrupt or truncated chart binary: header claims $noteCount notes '
                + '(needs ${Std.int(requiredBytes)} bytes) but file is only $fileSize bytes: $path';

        lanesInput.seek(HEADER_V2 + noteCount * 4, FileSeek.SeekBegin);

        var buffer = new NoteBuffer(1 << 16);
        var timeChunk = Bytes.alloc(CHUNK * 4);
        var laneChunk = Bytes.alloc(CHUNK);
        var runCounts = new Vector<Int>(LANES);
        for (l in 0...LANES)
            runCounts[l] = 0;
        var runValid = false;
        var runPos = 0;

        var done = 0;
        while (done < noteCount)
        {
            var n = noteCount - done;
            if (n > CHUNK)
                n = CHUNK;

            input.readFullBytes(timeChunk, 0, n * 4);
            lanesInput.readFullBytes(laneChunk, 0, n);

            for (i in 0...n)
            {
                var p = timeChunk.getInt32(i * 4);
                var lane = laneChunk.get(i);

                if (lane >= LANES)
                    throw 'corrupt chart binary: lane $lane out of range (0-${LANES - 1}) in $path';

                if (!runValid || p != runPos)
                {
                    if (runValid)
                        flushRun(buffer, runPos, runCounts);
                    runValid = true;
                    runPos = p;
                }

                runCounts[lane]++;
            }

            done += n;
            if (onProgress != null)
                onProgress(done / noteCount);
        }

        if (runValid)
            flushRun(buffer, runPos, runCounts);

        buffer.trim();
        buffer.total.set(0, noteCount);
        return buffer;
    }

    static function flushRun(buffer:NoteBuffer, pos:Int, runCounts:Vector<Int>):Void
    {
        for (lane in 0...LANES)
        {
            var c = runCounts[lane];
            if (c > 0)
            {
                buffer.pushCell(pos, lane, c, 0);
                runCounts[lane] = 0;
            }
        }
    }
}

private class V4Stream
{
    static inline var BUFFER_BYTES:Int = 1 << 16;

    public var lo:Int = 0;
    public var hi:Int = 0;

    var input:FileInput;
    var start:Int;
    var total:Int;
    var left:Int;
    var buf:Bytes;
    var pos:Int = 0;
    var end:Int = 0;
    var crc:Crc32 = new Crc32();
    var raw:Bool;
    var remaining:Int = 0;
    var repeating:Bool = false;
    var repLo:Int = 0;
    var repHi:Int = 0;

    public function new(path:String, offset:Int, length:Int, raw:Bool)
    {
        input = File.read(path, true);
        input.seek(offset, FileSeek.SeekBegin);
        start = offset;
        total = length;
        left = length;
        buf = Bytes.alloc(BUFFER_BYTES);
        this.raw = raw;
    }

    public static inline function unsigned(v:Int):Float
    {
        return v < 0 ? v + 4294967296.0 : v;
    }

    function fill():Void
    {
        if (left <= 0)
            throw 'corrupt chart binary: stream ended early';

        var n = left < BUFFER_BYTES ? left : BUFFER_BYTES;
        input.readFullBytes(buf, 0, n);
        crc.update(buf, 0, n);
        left -= n;
        pos = 0;
        end = n;
    }

    public inline function byte():Int
    {
        if (pos >= end)
            fill();
        return buf.get(pos++);
    }

    public function fixed32():Int
    {
        var b0 = byte();
        var b1 = byte();
        var b2 = byte();
        var b3 = byte();
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
    }

    public function varint():Void
    {
        var l = 0;
        var h = 0;
        var s = 0;

        while (true)
        {
            var b = byte();

            if (s == 63 && b > 1)
                throw 'corrupt chart binary: varint overflows 64 bits';

            var bits = b & 0x7F;
            if (s < 32)
            {
                l |= bits << s;
                if (s > 25)
                    h |= bits >>> (32 - s);
            }
            else
            {
                h |= bits << (s - 32);
            }

            if (b < 0x80)
                break;

            s += 7;
        }

        lo = l;
        hi = h;
    }

    inline function value():Void
    {
        if (raw)
        {
            lo = byte();
            hi = 0;
        }
        else
        {
            varint();
        }
    }

    public function item():Void
    {
        if (remaining == 0)
        {
            varint();
            if (hi != 0 || lo < 0)
                throw 'corrupt chart binary: run header out of range';

            if ((lo & 1) == 1)
            {
                remaining = (lo >>> 1) + 2;
                repeating = true;
                value();
                repLo = lo;
                repHi = hi;
            }
            else
            {
                remaining = (lo >>> 1) + 1;
                repeating = false;
            }
        }

        if (repeating)
        {
            lo = repLo;
            hi = repHi;
        }
        else
        {
            value();
        }

        remaining--;
    }

    public function offset():Int
    {
        return start + (total - left) - (end - pos);
    }

    public function finish(expectedCrc:Int):Void
    {
        if (pos != end || left != 0 || remaining != 0)
            throw 'corrupt chart binary: stream has unread or missing data';

        if (crc.get() != expectedCrc)
            throw 'corrupt chart binary: checksum mismatch';
    }

    public function close():Void
    {
        input.close();
    }
}
