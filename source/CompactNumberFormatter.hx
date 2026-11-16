package;

class CompactNumberFormatter
{
    static final ONES_SHORT:Array<String> =
        ['', 'mi', 'bi', 'tri', 'quadri', 'quinti', 'sexti', 'septi', 'octi', 'noni'];

    static final ONES_LONG:Array<{prefix:String, needsConnector:Bool}> = [
        {prefix: '', needsConnector: false},
        {prefix: 'un', needsConnector: false},
        {prefix: 'duo', needsConnector: false},
        {prefix: 'tre', needsConnector: true},
        {prefix: 'quattuor', needsConnector: false},
        {prefix: 'quin', needsConnector: false},
        {prefix: 'se', needsConnector: true},
        {prefix: 'septe', needsConnector: true},
        {prefix: 'octo', needsConnector: false},
        {prefix: 'nove', needsConnector: true},
    ];

    static final TENS:Array<{prefix:String, connectorA:String, connectorB:String}> = [
        {prefix: '', connectorA: '', connectorB: ''},
        {prefix: 'deci', connectorA: 'n', connectorB: ''},
        {prefix: 'viginti', connectorA: 'm', connectorB: 's'},
        {prefix: 'triginti', connectorA: 'n', connectorB: 's'},
        {prefix: 'quadraginti', connectorA: 'n', connectorB: 's'},
        {prefix: 'quinquaginti', connectorA: 'n', connectorB: 's'},
        {prefix: 'sexaginti', connectorA: 'n', connectorB: ''},
        {prefix: 'septuaginti', connectorA: 'n', connectorB: ''},
        {prefix: 'octoginti', connectorA: 'm', connectorB: 'x'},
        {prefix: 'nonaginti', connectorA: '', connectorB: ''},
    ];

    static final HUNDREDS:Array<{prefix:String, connectorA:String, connectorB:String}> = [
        {prefix: '', connectorA: '', connectorB: ''},
        {prefix: 'centi', connectorA: 'n', connectorB: 'x'},
        {prefix: 'ducenti', connectorA: 'n', connectorB: ''},
        {prefix: 'trecenti', connectorA: 'n', connectorB: 's'},
        {prefix: 'quadringenti', connectorA: 'n', connectorB: 's'},
        {prefix: 'quingenti', connectorA: 'n', connectorB: 's'},
        {prefix: 'sescenti', connectorA: 'n', connectorB: ''},
        {prefix: 'septingenti', connectorA: 'n', connectorB: ''},
        {prefix: 'octingenti', connectorA: 'm', connectorB: 'x'},
        {prefix: 'nongenti', connectorA: '', connectorB: ''},
    ];

    static inline final ROUNDING_GUARD:Float = 1e-7;

    public static function formatCompactNumber(number:Float):String
    {
        if (Math.isNaN(number) || !Math.isFinite(number))
            return Std.string(number);

        var magnitude:Int = -1;
        var num:Float = number;

        while (num >= 1000.0)
        {
            num /= 1000.0;
            magnitude++;
        }

        var compactValue:Float = Math.floor(num * 100 + ROUNDING_GUARD) / 100;

        if (compactValue >= 1000.0)
        {
            compactValue /= 1000.0;
            magnitude++;
        }

        if (magnitude == -1)
            return Std.string(compactValue);

        if (magnitude == 0)
            return Std.string(compactValue) + " thousand";

        return Std.string(compactValue) + " " + buildIllionSuffix(magnitude) + "llion";
    }

    static function buildIllionSuffix(magnitude:Int):String
    {
        var onesIndex:Int = magnitude % 10;
        var tensIndex:Int = Std.int(magnitude / 10) % 10;
        var hundredsIndex:Int = Std.int(magnitude / 100);
        var adjacent = (tensIndex == 0 && hundredsIndex > 0) ? HUNDREDS[hundredsIndex] : TENS[tensIndex];

        var onesPrefix:String;
        if (magnitude <= 10)
        {
            onesPrefix = ONES_SHORT[onesIndex];
        }
        else
        {
            var ones = ONES_LONG[onesIndex];
            var connector:String = chooseConnector(onesIndex, adjacent.connectorA, adjacent.connectorB);
            onesPrefix = ones.prefix + (ones.needsConnector ? connector : '');
        }

        return onesPrefix + TENS[tensIndex].prefix + HUNDREDS[hundredsIndex].prefix;
    }

    static function chooseConnector(onesIndex:Int, connectorA:String, connectorB:String):String
    {
        if (onesIndex != 3 && onesIndex != 6)
            return connectorA;

        if (onesIndex == 3 && connectorB == 'x')
            return 's';

        return connectorB;
    }
}
