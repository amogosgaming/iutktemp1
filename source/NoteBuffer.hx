package;

import haxe.ds.Vector;
import haxe.io.Bytes;

class NoteBuffer
{
    public static inline var MAX_SAFE_CELLS:Int = (1 << 28) - 1;
    static inline var MIN_CAPACITY:Int = 16;

    public var positions:Vector<Int>;
    public var lanes:Bytes;
    public var counts:Bytes;
    public var length(default, null):Int = 0;

    public var total:U64 = new U64();

    var capacity:Int;

    public function new(initialCapacity:Int = 1 << 16)
    {
        capacity = initialCapacity < MIN_CAPACITY ? MIN_CAPACITY : initialCapacity;

        if (capacity > MAX_SAFE_CELLS)
            throw 'NoteBuffer capacity $capacity exceeds the safe allocation limit ($MAX_SAFE_CELLS)';

        positions = new Vector<Int>(capacity);
        lanes = Bytes.alloc(capacity);
        counts = Bytes.alloc(capacity * 8);
    }

    public inline function setLength(n:Int):Void
    {
        length = n;
    }

    public inline function countLo(i:Int):Int
    {
        return counts.getInt32(i << 3);
    }

    public inline function countHi(i:Int):Int
    {
        return counts.getInt32((i << 3) + 4);
    }

    public inline function pushCell(position:Int, lane:Int, lo:Int, hi:Int):Void
    {
        if (length >= capacity)
            grow();
        positions[length] = position;
        lanes.set(length, lane);
        counts.setInt32(length << 3, lo);
        counts.setInt32((length << 3) + 4, hi);
        length++;
    }

    public function trim():Void
    {
        if (capacity == length || length < MIN_CAPACITY)
            return;

        resize(length);
    }

    function grow():Void
    {
        if (capacity >= MAX_SAFE_CELLS)
            throw 'NoteBuffer is full: the safe allocation limit ($MAX_SAFE_CELLS) was reached';

        var newCap = capacity > (MAX_SAFE_CELLS >> 1) ? MAX_SAFE_CELLS : capacity * 2;
        resize(newCap);
    }

    function resize(newCap:Int):Void
    {
        var newPos = new Vector<Int>(newCap);
        var newLane = Bytes.alloc(newCap);
        var newCounts = Bytes.alloc(newCap * 8);
        Vector.blit(positions, 0, newPos, 0, length);
        newLane.blit(0, lanes, 0, length);
        newCounts.blit(0, counts, 0, length * 8);
        positions = newPos;
        lanes = newLane;
        counts = newCounts;
        capacity = newCap;
    }

    public inline function swap(i:Int, j:Int):Void
    {
        var tp = positions[i];
        positions[i] = positions[j];
        positions[j] = tp;

        var tl = lanes.get(i);
        lanes.set(i, lanes.get(j));
        lanes.set(j, tl);

        var i8 = i << 3;
        var j8 = j << 3;
        var a0 = counts.getInt32(i8);
        var a1 = counts.getInt32(i8 + 4);
        counts.setInt32(i8, counts.getInt32(j8));
        counts.setInt32(i8 + 4, counts.getInt32(j8 + 4));
        counts.setInt32(j8, a0);
        counts.setInt32(j8 + 4, a1);
    }
}
