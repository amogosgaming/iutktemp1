package;

import haxe.Int32;
import haxe.Int64;

final class U64
{
    public var hi:Int;
    public var lo:Int;

    public inline function new(hi:Int = 0, lo:Int = 0)
    {
        this.hi = hi;
        this.lo = lo;
    }

    public inline function set(h:Int, l:Int):Void
    {
        hi = h;
        lo = l;
    }

    public inline function copyFrom(o:U64):Void
    {
        hi = o.hi;
        lo = o.lo;
    }

    public inline function equals(o:U64):Bool
    {
        return hi == o.hi && lo == o.lo;
    }

    public inline function isZero():Bool
    {
        return hi == 0 && lo == 0;
    }

    public inline function addParts(h:Int, l:Int):Void
    {
        var nl = lo + l;
        if (Int32.ucompare(nl, lo) < 0)
            hi++;
        lo = nl;
        hi += h;
    }

    public function addPartsChecked(h:Int, l:Int):Bool
    {
        var carry = 0;
        var nl = lo + l;
        if (Int32.ucompare(nl, lo) < 0)
            carry = 1;

        var h1 = hi + h;
        var overflow = Int32.ucompare(h1, hi) < 0;
        var h2 = h1 + carry;
        if (Int32.ucompare(h2, h1) < 0)
            overflow = true;

        lo = nl;
        hi = h2;
        return overflow;
    }

    public inline function addU64(o:U64):Void
    {
        addParts(o.hi, o.lo);
    }

    public inline function setDiff(a:U64, b:U64):Void
    {
        var nl = a.lo - b.lo;
        var borrow = Int32.ucompare(a.lo, b.lo) < 0 ? 1 : 0;
        hi = a.hi - b.hi - borrow;
        lo = nl;
    }

    public function toFloat():Float
    {
        return u32(hi) * 4294967296.0 + u32(lo);
    }

    static inline function u32(v:Int):Float
    {
        return v < 0 ? v + 4294967296.0 : v;
    }

    static inline function wrap32(f:Float):Int
    {
        return f >= 2147483648.0 ? Std.int(f - 4294967296.0) : Std.int(f);
    }

    public static function fromFloat(v:Float):U64
    {
        if (!(v > 0))
            return new U64(0, 0);
        if (v >= 18446744073709551615.0)
            return new U64(-1, -1);

        var hiF = Math.ffloor(v / 4294967296.0);
        var loF = Math.ffloor(v - hiF * 4294967296.0);
        return new U64(wrap32(hiF), wrap32(loF));
    }

    public function toString():String
    {
        if (hi == 0 && lo >= 0)
            return Std.string(lo);

        var x = Int64.make(hi, lo);
        if (!Int64.isNeg(x))
            return Int64.toStr(x);

        var q = (x >>> 1) / Int64.ofInt(5);
        var r = (x - q * Int64.ofInt(10)).low;
        return Int64.toStr(q) + Std.string(r);
    }

    public static function group(digits:String):String
    {
        var len = digits.length;
        var buf = new StringBuf();
        for (i in 0...len)
        {
            if (i > 0 && (len - i) % 3 == 0)
                buf.add(',');
            buf.add(digits.charAt(i));
        }
        return buf.toString();
    }

    public inline function toGroupedString():String
    {
        return group(toString());
    }

    public function toDisplayString():String
    {
        var f = toFloat();
        return f < 1e12 ? toGroupedString() : CompactNumberFormatter.formatCompactNumber(f);
    }
}
