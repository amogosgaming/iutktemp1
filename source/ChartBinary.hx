package;

import haxe.ds.Vector;
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

            if (version == 3)
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
