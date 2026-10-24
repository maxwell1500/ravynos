/*
 * CalcEngine - the calculation engine behind Calculator.app.
 *
 * The engine is pure computation: it keeps the expression the user is
 * building, evaluates it with a recursive descent parser and reports the
 * result, the tape line and the programmer readouts.  No UI lives here.
 */

#import "CalcEngine.h"
#import <math.h>
#import <stdlib.h>
#import <string.h>

static const double kPi = 3.14159265358979323846;
static const double kE = 2.71828182845904523536;

/* ------------------------------------------------------------------ */
/* Expression evaluation                                               */
/* ------------------------------------------------------------------ */

typedef struct {
    const char *text;
    int pos;
    BOOL failed;
} CalcParser;

static double _parseExpression(CalcParser *p);

static void _skipSpace(CalcParser *p) {
    while(p->text[p->pos] == ' ' || p->text[p->pos] == '\t')
        p->pos++;
}

static double _parsePrimary(CalcParser *p) {
    double value = 0;

    _skipSpace(p);
    if(p->text[p->pos] == '-') {
        p->pos++;
        return -_parsePrimary(p);
    }
    if(p->text[p->pos] == '+') {
        p->pos++;
        return _parsePrimary(p);
    }
    if(p->text[p->pos] == '(') {
        p->pos++;
        value = _parseExpression(p);
        _skipSpace(p);
        if(p->text[p->pos] == ')')
            p->pos++;
        else
            p->failed = YES;
        return value;
    }
    if(p->text[p->pos] == 'p' && strncmp(p->text + p->pos, "pi", 2) == 0) {
        p->pos += 2;
        return kPi;
    }
    if(p->text[p->pos] == 'e' && strncmp(p->text + p->pos, "e", 1) == 0 &&
       !(p->text[p->pos + 1] == 'x' || p->text[p->pos + 1] == 'E')) {
        /* "e" is the constant only when it is not the exponent marker. */
        if(!(p->text[p->pos - 1] == '0' || p->text[p->pos - 1] == '1' ||
             p->text[p->pos - 1] == '2' || p->text[p->pos - 1] == '3' ||
             p->text[p->pos - 1] == '4' || p->text[p->pos - 1] == '5' ||
             p->text[p->pos - 1] == '6' || p->text[p->pos - 1] == '7' ||
             p->text[p->pos - 1] == '8' || p->text[p->pos - 1] == '9' ||
             p->text[p->pos - 1] == '.')) {
            p->pos++;
            return kE;
        }
    }
    {
        char *end = NULL;
        value = strtod(p->text + p->pos, &end);
        if(end == p->text + p->pos) {
            p->failed = YES;
            return 0;
        }
        p->pos = (int)(end - p->text);
    }
    return value;
}

static double _parsePower(CalcParser *p) {
    double base = _parsePrimary(p);
    _skipSpace(p);
    if(p->text[p->pos] == '^') {
        p->pos++;
        /* right associative: 2^3^2 == 2^(3^2) */
        return pow(base, _parsePower(p));
    }
    return base;
}

static double _parseTerm(CalcParser *p) {
    double value = _parsePower(p);

    for(;;) {
        _skipSpace(p);
        switch(p->text[p->pos]) {
            case '*':
                p->pos++;
                value *= _parsePower(p);
                break;
            case '/':
                p->pos++;
                {
                    double divisor = _parsePower(p);
                    if(divisor == 0) {
                        p->failed = YES;
                        return 0;
                    }
                    value /= divisor;
                }
                break;
            case '%':
                p->pos++;
                {
                    double divisor = _parsePower(p);
                    if(divisor == 0) {
                        p->failed = YES;
                        return 0;
                    }
                    value = fmod(value, divisor);
                }
                break;
            default:
                return value;
        }
    }
}

static double _parseExpression(CalcParser *p) {
    double value = _parseTerm(p);

    for(;;) {
        _skipSpace(p);
        switch(p->text[p->pos]) {
            case '+':
                p->pos++;
                value += _parseTerm(p);
                break;
            case '-':
                p->pos++;
                value -= _parseTerm(p);
                break;
            default:
                return value;
        }
    }
}

static double _evaluate(NSString *expression, BOOL *ok) {
    CalcParser parser;
    const char *text = [expression UTF8String];
    double value;

    parser.text = text != NULL ? text : "";
    parser.pos = 0;
    parser.failed = NO;
    value = _parseExpression(&parser);
    _skipSpace(&parser);
    if(parser.failed || parser.text[parser.pos] != 0)
        value = 0;
    if(ok != NULL)
        *ok = !parser.failed;
    return value;
}

/* ------------------------------------------------------------------ */

@interface CalcEngine ()
@property (nonatomic, strong) NSMutableString *entry;
@property (nonatomic, strong) NSMutableString *expressionText;
@property (nonatomic, assign) double accumulator;
@property (nonatomic, copy) NSString *pendingOperator;
@property (nonatomic, assign) double pendingOperand;
@property (nonatomic, assign) BOOL justEvaluated;
@property (nonatomic, copy) NSString *repeatOperator;
@property (nonatomic, assign) double repeatOperand;
@property (nonatomic, assign) BOOL exponentMode;
@property (nonatomic, strong) NSMutableString *progExpression;
@property (nonatomic, strong) NSMutableString *tapeLine;
@property (nonatomic, assign) BOOL progEnteringFlag;
@property (nonatomic, strong) NSMutableString *progEntryText;
@end

@implementation CalcEngine

- (id)init {
    self = [super init];
    if(self != nil) {
        _entry = [[NSMutableString alloc] init];
        _expressionText = [[NSMutableString alloc] init];
        _progExpression = [[NSMutableString alloc] init];
        _progEntryText = [[NSMutableString alloc] init];
        _tapeLine = [[NSMutableString alloc] init];
        _mode = CalcModeStandard;
        _angleMode = AngleRadians;
        _wordSize = WordSize64;
        _inputBase = 10;
        _display = @"0";
    }
    return self;
}

- (NSString *)expression {
    return [NSString stringWithFormat:@"%@%@", _expressionText, _entry];
}

- (NSString *)lastTapeLine {
    return [NSString stringWithFormat:@"%@", _tapeLine];
}

#pragma mark - Formatting

- (NSString *)_formatDouble:(double)value {
    if(value == (long long)value && fabs(value) < 1e15)
        return [NSString stringWithFormat:@"%lld", (long long)value];
    return [NSString stringWithFormat:@"%.10g", value];
}

- (void)_syncDisplay {
    if([_entry length] > 0) {
        _display = [_entry copy];
        return;
    }
    if([_expressionText length] > 0) {
        _display = [_expressionText copy];
        return;
    }
    _display = @"0";
}

#pragma mark - Standard / scientific entry

- (void)clear {
    [_entry setString:@""];
    [_expressionText setString:@""];
    _pendingOperator = nil;
    _justEvaluated = NO;
    _repeatOperator = nil;
    _exponentMode = NO;
    _accumulator = 0;
    _display = @"0";
}

- (void)clearEntry {
    [_entry setString:@""];
    _exponentMode = NO;
    [self _syncDisplay];
}

- (void)inputDigit:(int)d {
    if(_justEvaluated) {
        [_entry setString:@""];
        [_expressionText setString:@""];
        _justEvaluated = NO;
    }
    if(_exponentMode) {
        [_entry appendFormat:@"%d", d];
    } else if([_entry isEqualToString:@"0"]) {
        [_entry setString:[NSString stringWithFormat:@"%d", d]];
    } else {
        [_entry appendFormat:@"%d", d];
    }
    [self _syncDisplay];
}

- (void)inputDecimalPoint {
    if(_justEvaluated) {
        [_entry setString:@""];
        [_expressionText setString:@""];
        _justEvaluated = NO;
    }
    if([_entry rangeOfString:@"."].location != NSNotFound)
        return;
    if([_entry length] == 0)
        [_entry setString:@"0"];
    [_entry appendString:@"."];
    [self _syncDisplay];
}

- (void)inputEE {
    if([_entry length] == 0)
        [_entry setString:@"1"];
    if([_entry rangeOfString:@"e"].location == NSNotFound)
        [_entry appendString:@"e"];
    _exponentMode = YES;
    [self _syncDisplay];
}

- (void)deleteLastDigit {
    if([_entry length] > 0) {
        [_entry deleteCharactersInRange:NSMakeRange([_entry length] - 1, 1)];
        [self _syncDisplay];
    }
}

- (void)toggleSign {
    if([_entry length] == 0) {
        if([_expressionText length] > 0) {
            [_expressionText insertString:@"-" atIndex:0];
            [self _syncDisplay];
        }
        return;
    }
    if([_entry hasPrefix:@"-"])
        [_entry deleteCharactersInRange:NSMakeRange(0, 1)];
    else
        [_entry insertString:@"-" atIndex:0];
    [self _syncDisplay];
}

- (void)percent {
    double value = [_entry doubleValue];

    if([_entry length] == 0)
        value = _accumulator;

    if(_pendingOperator != nil &&
       ([_pendingOperator isEqualToString:@"+"] ||
        [_pendingOperator isEqualToString:@"-"] ||
        [_pendingOperator isEqualToString:@"×"] ||
        [_pendingOperator isEqualToString:@"*"] ||
        [_pendingOperator isEqualToString:@"÷"] ||
        [_pendingOperator isEqualToString:@"/"])) {
        value = _accumulator * value / 100.0;
        [_entry setString:[self _formatDouble:value]];
    } else {
        value = value / 100.0;
        [_entry setString:[self _formatDouble:value]];
    }
    [self _syncDisplay];
}

- (void)inputConstant:(NSString *)name {
    if([name isEqualToString:@"pi"])
        [_entry setString:[self _formatDouble:kPi]];
    else if([name isEqualToString:@"e"])
        [_entry setString:[self _formatDouble:kE]];
    [self _syncDisplay];
}

/* Move the current entry into the expression and append the operator. */
- (void)_flushEntry {
    if([_entry length] > 0) {
        [_expressionText appendString:_entry];
        [_entry setString:@""];
    }
}

- (void)inputOperator:(NSString *)op {
    if(_justEvaluated) {
        /* A new operation starts from the result. */
        _justEvaluated = NO;
    }
    if([_entry length] == 0 && [_expressionText length] == 0) {
        /* Nothing to compute yet: start the expression with the operator's
         * identity so "5 +" is possible. */
        [_expressionText setString:@"0"];
    }
    /* percent needs the left operand as its base ("5 + 10 %" is 5.5, not 0):
     * remember it before the entry is folded into the expression. */
    if([_entry length] > 0)
        _accumulator = [_entry doubleValue];

    [self _flushEntry];
    if([_expressionText hasSuffix:@"+"] || [_expressionText hasSuffix:@"-"] ||
       [_expressionText hasSuffix:@"×"] || [_expressionText hasSuffix:@"÷"] ||
       [_expressionText hasSuffix:@"*"] || [_expressionText hasSuffix:@"/"]) {
        /* Replace the trailing operator. */
        [_expressionText deleteCharactersInRange:
            NSMakeRange([_expressionText length] - 1, 1)];
    }
    [_expressionText appendFormat:@"%@", op];
    _pendingOperator = op;

    _exponentMode = NO;
    [self _syncDisplay];
}

- (void)inputOpenParen {
    [self _flushEntry];
    [_expressionText appendString:@"("];
    [self _syncDisplay];
}

- (void)inputCloseParen {
    [self _flushEntry];
    [_expressionText appendString:@")"];
    [self _syncDisplay];
}

/* The functions act on the value that is on the display. */
- (void)inputFunction:(NSString *)fn {
    double value = [_entry doubleValue];
    double result = value;
    double angle = _angleMode == AngleDegrees ? value * M_PI / 180.0 : value;

    if([_entry length] == 0 && [_expressionText length] > 0 && _justEvaluated)
        value = _accumulator;

    if([fn isEqualToString:@"sin"])
        result = sin(angle);
    else if([fn isEqualToString:@"cos"])
        result = cos(angle);
    else if([fn isEqualToString:@"tan"])
        result = tan(angle);
    else if([fn isEqualToString:@"asin"])
        result = asin(value);
    else if([fn isEqualToString:@"acos"])
        result = acos(value);
    else if([fn isEqualToString:@"atan"])
        result = atan(value);
    else if([fn isEqualToString:@"ln"])
        result = log(value);
    else if([fn isEqualToString:@"log"])
        result = log10(value);
    else if([fn isEqualToString:@"exp"])
        result = exp(value);
    else if([fn isEqualToString:@"pow10"])
        result = pow(10.0, value);
    else if([fn isEqualToString:@"sqrt"])
        result = sqrt(value);
    else if([fn isEqualToString:@"cbrt"])
        result = cbrt(value);
    else if([fn isEqualToString:@"inv"])
        result = value != 0 ? 1.0 / value : 0;
    else if([fn isEqualToString:@"fact"]) {
        long long n = (long long)value;
        result = 1;
        if(n < 0 || n > 170) {
            result = 0;
        } else {
            for(long long i = 2; i <= n; i++)
                result *= i;
        }
    } else if([fn isEqualToString:@"sqr"])
        result = value * value;
    else if([fn isEqualToString:@"cube"])
        result = value * value * value;

    if(_angleMode == AngleDegrees &&
       ([fn isEqualToString:@"asin"] || [fn isEqualToString:@"acos"] ||
        [fn isEqualToString:@"atan"]))
        result = result * 180.0 / M_PI;

    [_entry setString:[self _formatDouble:result]];
    _accumulator = result;
    [self _syncDisplay];
}

- (void)inputEquals {
    NSString *line;
    BOOL ok = YES;
    double value;

    [self _flushEntry];

    if([_expressionText length] == 0) {
        value = [_entry doubleValue];
        line = [NSString stringWithFormat:@"%@ = %@", _expressionText, [self _formatDouble:value]];
        [_tapeLine setString:line];
        _justEvaluated = YES;
        return;
    }

    /* A repeated "=" repeats the last operation. */
    if(_justEvaluated && _repeatOperator != nil) {
        NSString *repeated = [NSString stringWithFormat:@"%@%@%@",
                              _expressionText, _repeatOperator,
                              [self _formatDouble:_repeatOperand]];
        value = _evaluate(repeated, &ok);
        line = [NSString stringWithFormat:@"%@ = %@", repeated, [self _formatDouble:value]];
        [_expressionText setString:repeated];
        [_entry setString:[self _formatDouble:value]];
        _accumulator = value;
        _repeatOperand = _accumulator;
        [_tapeLine setString:line];
        [self _syncDisplay];
        return;
    }

    line = [NSString stringWithFormat:@"%@ = %@", _expressionText, @"?"];
    value = _evaluate(_expressionText, &ok);
    line = [NSString stringWithFormat:@"%@ = %@", _expressionText, [self _formatDouble:value]];

    /* Remember the operation for a repeated "=". */
    if([_expressionText length] > 0) {
        NSRange lastOp = [_expressionText rangeOfString:@"×" options:NSBackwardsSearch];
        if(lastOp.location == NSNotFound)
            lastOp = [_expressionText rangeOfString:@"÷" options:NSBackwardsSearch];
        if(lastOp.location == NSNotFound)
            lastOp = [_expressionText rangeOfString:@"+" options:NSBackwardsSearch];
        if(lastOp.location == NSNotFound)
            lastOp = [_expressionText rangeOfString:@"-" options:NSBackwardsSearch];
        if(lastOp.location != NSNotFound && lastOp.location + 1 < [_expressionText length]) {
            /* Operator only: keeping the operand in _repeatOperator made the
             * next "=" append it again ("+3" + "3"). */
            _repeatOperator = [[_expressionText substringFromIndex:lastOp.location] substringToIndex:1];
            _repeatOperand = [[_expressionText substringFromIndex:lastOp.location + 1] doubleValue];
        }
    }

    [_expressionText setString:@""];
    [_entry setString:[self _formatDouble:value]];
    _accumulator = value;
    _pendingOperator = nil;
    _justEvaluated = YES;
    [_tapeLine setString:line];
    [self _syncDisplay];
}

#pragma mark - Programmer mode

- (unsigned long long)wordMask {
    switch(_wordSize) {
        case WordSize8:  return 0xFFULL;
        case WordSize16: return 0xFFFFULL;
        case WordSize32: return 0xFFFFFFFFULL;
        default:         return 0xFFFFFFFFFFFFFFFFULL;
    }
}

- (BOOL)progEntering {
    return _progEnteringFlag;
}

- (void)setProgEntering:(BOOL)v {
    _progEnteringFlag = v;
}

- (NSMutableString *)progEntry {
    return _progEntryText;
}

- (void)inputProgrammerDigit:(int)d {
    if(_justEvaluated) {
        [_progEntryText setString:@""];
        _justEvaluated = NO;
    }
    /* Reject digits the selected base cannot represent: in Dec mode "A" is
     * not an entry, and in Bin mode only 0 and 1 are. */
    if(d < 0 || d >= _inputBase)
        return;
    if(d >= 10)
        [_progEntryText appendFormat:@"%c", 'A' + d - 10];
    else
        [_progEntryText appendFormat:@"%d", d];
    _progValue = (unsigned long long)strtoull([_progEntryText UTF8String], NULL,
                                              _inputBase) & [self wordMask];
    _display = [self hexReadout];
}

- (void)inputProgrammerOperator:(NSString *)op {
    unsigned long long left;

    if([_progEntryText length] == 0) {
        left = _progValue;
    } else {
        /* The entry is in the selected base; Dec "10" must not parse as 0x10. */
        left = (unsigned long long)strtoull([_progEntryText UTF8String], NULL,
                                            _inputBase);
    }
    left &= [self wordMask];

    if([op isEqualToString:@"not"]) {
        _progValue = (~left) & [self wordMask];
        [_progEntryText setString:@""];
        _display = [self hexReadout];
        return;
    }

    if([_progExpression length] > 0)
        [_progExpression appendString:@" "];
    [_progExpression appendFormat:@"%llX", left];
    [_progExpression appendFormat:@" %@ ", op];
    [_progEntryText setString:@""];
    _display = [self hexReadout];
}

- (void)inputProgrammerEquals {
    unsigned long long left, right, result = 0;
    NSEnumerator *parts;
    NSString *op;

    if([_progExpression length] == 0) {
        _progValue &= [self wordMask];
        _display = [self hexReadout];
        return;
    }

    parts = [[_progExpression componentsSeparatedByString:@" "] objectEnumerator];
    left = (unsigned long long)strtoull([[parts nextObject] UTF8String], NULL, 16);
    op = [parts nextObject];
    /* The operator only records the left operand; the right one is whatever
     * was typed afterwards, which lives in _progValue (the expression has an
     * empty second operand). */
    if([_progEntryText length] > 0)
        right = _progValue;
    else
        right = (unsigned long long)strtoull([[parts nextObject] UTF8String], NULL, 16);

    if([op isEqualToString:@"+"])
        result = left + right;
    else if([op isEqualToString:@"-"])
        result = left - right;
    else if([op isEqualToString:@"*"])
        result = left * right;
    else if([op isEqualToString:@"/"])
        result = right != 0 ? left / right : 0;
    else if([op isEqualToString:@"%"])
        result = right != 0 ? left % right : 0;
    else if([op isEqualToString:@"&"])
        result = left & right;
    else if([op isEqualToString:@"|"])
        result = left | right;
    else if([op isEqualToString:@"^"])
        result = left ^ right;
    else if([op isEqualToString:@"nor"])
        result = ~(left | right);
    else if([op isEqualToString:@"<<"])
        result = left << (right & 63);
    else if([op isEqualToString:@">>"])
        result = left >> (right & 63);
    else if([op isEqualToString:@"rol"]) {
        unsigned long long shift = right & 63;
        unsigned long long mask = [self wordMask];
        result = ((left << shift) | (left >> ((64 - shift) & 63))) & mask;
    } else if([op isEqualToString:@"ror"]) {
        unsigned long long shift = right & 63;
        unsigned long long mask = [self wordMask];
        result = ((left >> shift) | (left << ((64 - shift) & 63))) & mask;
    }

    _progValue = result & [self wordMask];
    [_progExpression setString:@""];
    [_progEntryText setString:@""];
    _display = [self hexReadout];
}

- (void)setBit:(int)bit value:(BOOL)v {
    unsigned long long mask = 1ULL << bit;

    if(v)
        _progValue |= mask;
    else
        _progValue &= ~mask;
    _progValue &= [self wordMask];
    _display = [self hexReadout];
}

#pragma mark - Readouts

- (NSString *)hexReadout {
    return [NSString stringWithFormat:@"%llX", _progValue & [self wordMask]];
}

- (NSString *)decReadout {
    return [NSString stringWithFormat:@"%llu", _progValue & [self wordMask]];
}

- (NSString *)octReadout {
    return [NSString stringWithFormat:@"%llo", _progValue & [self wordMask]];
}

- (NSString *)binReadout {
    unsigned long long value = _progValue & [self wordMask];
    char bits[70];
    int width = 64;
    int i;

    if(_wordSize == WordSize8) width = 8;
    else if(_wordSize == WordSize16) width = 16;
    else if(_wordSize == WordSize32) width = 32;

    for(i = 0; i < width; i++)
        bits[i] = (value & (1ULL << (width - 1 - i))) ? '1' : '0';
    bits[width] = 0;
    return [NSString stringWithFormat:@"%s", bits];
}

#pragma mark - Memory and pasteboard

- (void)inputPastedString:(NSString *)s {
    NSString *trimmed = [s stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceCharacterSet]];

    if([trimmed length] == 0)
        return;

    if(_mode == CalcModeProgrammer) {
        const char *text = [trimmed UTF8String];
        int base = 10;
        if(text[0] == '0' && (text[1] == 'x' || text[1] == 'X')) {
            base = 16;
            text += 2;
        }
        _progValue = (unsigned long long)strtoull(text, NULL, base) & [self wordMask];
        [_progEntryText setString:@""];
        _display = [self hexReadout];
        return;
    }

    [_entry setString:trimmed];
    _accumulator = [trimmed doubleValue];
    [self _syncDisplay];
}

- (void)memoryClear {
    _memory = 0;
    _progMemory = 0;
}

- (void)memoryRecall {
    if(_mode == CalcModeProgrammer) {
        _progValue = _progMemory & [self wordMask];
        _display = [self hexReadout];
    } else {
        [_entry setString:[self _formatDouble:_memory]];
        [self _syncDisplay];
    }
}

- (void)memoryAdd {
    if(_mode == CalcModeProgrammer)
        _progMemory = (_progMemory + _progValue) & [self wordMask];
    else
        _memory += [_entry doubleValue];
}

- (void)memorySubtract {
    if(_mode == CalcModeProgrammer)
        _progMemory = (_progMemory - _progValue) & [self wordMask];
    else
        _memory -= [_entry doubleValue];
}

@end
