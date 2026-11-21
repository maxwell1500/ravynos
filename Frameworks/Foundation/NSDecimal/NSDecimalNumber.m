/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <Foundation/NSDecimalNumber.h>
#import <Foundation/NSString.h>
#import <Foundation/NSMutableString.h>
#import <Foundation/NSRaise.h>
#import <Foundation/NSException.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

NSString * const NSDecimalNumberDivideByZeroException=@"NSDecimalNumberDivideByZeroException";
NSString * const NSDecimalNumberUnderflowException=@"NSDecimalNumberUnderflowException";
NSString * const NSDecimalNumberOverflowException=@"NSDecimalNumberOverflowException";
NSString * const NSDecimalNumberExactnessException=@"NSDecimalNumberExactnessException";

#define NSDecimalScaleLimit 19
#define NSDecimalPow10_18 ((__int128)1000000000000000000LL)

static NSDecimalValue NSDecimalMake(uint64_t mantissa,int16_t exponent,BOOL negative) {
   NSDecimalValue result;

   result.mantissa=mantissa;
   result.exponent=exponent;
   result.isNegative=(negative && mantissa!=0)?1:0;
   result.isNaN=0;
   return result;
}

static NSDecimalValue NSDecimalMakeNaN(void) {
   NSDecimalValue result=NSDecimalValueZero;

   result.isNaN=1;
   return result;
}

static NSDecimalValue NSDecimalFromWide(__int128 magnitude,int16_t exponent,BOOL negative) {
   while(magnitude>(__int128)UINT64_MAX){
    __int128 quotient=magnitude/10;
    __int128 remainder=magnitude%10;

    if(remainder>=5)
     quotient++;
    magnitude=quotient;
    exponent++;
   }

   return NSDecimalMake((uint64_t)magnitude,exponent,negative);
}

static __int128 NSDecimalScaledMantissa(NSDecimalValue value,int16_t exponent) {
   __int128 result=(__int128)value.mantissa;

   while(value.exponent>exponent){
    result*=10;
    value.exponent--;
   }

   return result;
}

static NSDecimalValue NSDecimalAdd(NSDecimalValue a,NSDecimalValue b) {
   int16_t exponent;
   __int128 va,vb,sum;
   BOOL negative;

   if(a.isNaN || b.isNaN)
    return NSDecimalMakeNaN();
   if(a.mantissa==0)
    return b;
   if(b.mantissa==0)
    return a;

   exponent=(a.exponent<b.exponent)?a.exponent:b.exponent;
   if((int)(a.exponent-exponent)>NSDecimalScaleLimit)
    exponent=a.exponent-NSDecimalScaleLimit;
   if((int)(b.exponent-exponent)>NSDecimalScaleLimit)
    exponent=b.exponent-NSDecimalScaleLimit;

   va=NSDecimalScaledMantissa(a,exponent);
   vb=NSDecimalScaledMantissa(b,exponent);

   if(a.isNegative)
    va=-va;
   if(b.isNegative)
    vb=-vb;

   sum=va+vb;
   negative=(sum<0);
   if(negative)
    sum=-sum;

   return NSDecimalFromWide(sum,exponent,negative);
}

static NSDecimalValue NSDecimalSubtract(NSDecimalValue a,NSDecimalValue b) {
   b.isNegative=!b.isNegative;
   return NSDecimalAdd(a,b);
}

static NSDecimalValue NSDecimalMultiply(NSDecimalValue a,NSDecimalValue b) {
   __int128 product;
   int exponent;

   if(a.isNaN || b.isNaN)
    return NSDecimalMakeNaN();

   product=(__int128)a.mantissa*(__int128)b.mantissa;
   exponent=(int)a.exponent+(int)b.exponent;

   if(exponent>INT16_MAX)
    exponent=INT16_MAX;
   if(exponent<INT16_MIN)
    exponent=INT16_MIN;

   return NSDecimalFromWide(product,(int16_t)exponent,(a.isNegative!=b.isNegative));
}

static NSDecimalValue NSDecimalDivide(NSDecimalValue a,NSDecimalValue b,id self,SEL _cmd) {
   __int128 numerator,quotient;
   int exponent;

   if(a.isNaN || b.isNaN)
    return NSDecimalMakeNaN();

   if(b.mantissa==0)
    [NSException raise:NSDecimalNumberDivideByZeroException
                format:@"-[%@ %s] divide by zero",[self class],sel_getName(_cmd)];

   if(a.mantissa==0)
    return NSDecimalValueZero;

   numerator=(__int128)a.mantissa*NSDecimalPow10_18;
   quotient=numerator/(__int128)b.mantissa;
   exponent=(int)a.exponent-(int)b.exponent-18;

   if(exponent>INT16_MAX)
    exponent=INT16_MAX;
   if(exponent<INT16_MIN)
    exponent=INT16_MIN;

   return NSDecimalFromWide(quotient,(int16_t)exponent,(a.isNegative!=b.isNegative));
}

static BOOL NSDecimalFromString(NSString *string,NSDecimalValue *valuep) {
   const char *utf8=[string UTF8String];
   const char *p;
   uint64_t mantissa=0;
   int fractionDigits=0;
   long extraIntegerDigits=0;
   BOOL negative=NO,seenDot=NO,seenDigit=NO;
   long exponent=0;

   if(utf8==NULL)
    return NO;

   for(p=utf8;*p==' ' || *p=='\t' || *p=='\n' || *p=='\r';p++)
    ;

   if(*p=='+' || *p=='-'){
    negative=(*p=='-');
    p++;
   }

   for(;*p!='\0';p++){
    if(*p>='0' && *p<='9'){
     int digit=*p-'0';

     seenDigit=YES;
     if(mantissa>(UINT64_MAX-9)/10){
      /* Keep the magnitude's place value; only the low digits are lost. */
      if(!seenDot)
       extraIntegerDigits++;
     }
     else {
      mantissa=mantissa*10+digit;
      if(seenDot)
       fractionDigits++;
     }
    }
    else if(*p=='.' && !seenDot)
     seenDot=YES;
    else
     break;
   }

   if(!seenDigit)
    return NO;

   if(*p=='e' || *p=='E'){
    BOOL exponentNegative=NO;
    long parsed=0;
    BOOL seenExponentDigit=NO;

    p++;
    if(*p=='+' || *p=='-'){
     exponentNegative=(*p=='-');
     p++;
    }

    for(;*p>='0' && *p<='9';p++){
     seenExponentDigit=YES;
     if(parsed<100000)
      parsed=parsed*10+(*p-'0');
    }

    if(!seenExponentDigit)
     return NO;

    exponent+=exponentNegative?-parsed:parsed;
   }

   for(;*p==' ' || *p=='\t' || *p=='\n' || *p=='\r';p++)
    ;

   if(*p!='\0')
    return NO;

   exponent+=extraIntegerDigits-fractionDigits;
   if(exponent>INT16_MAX || exponent<INT16_MIN)
    return NO;

   *valuep=NSDecimalMake(mantissa,(int16_t)exponent,negative);
   return YES;
}

/* ---- conversion across the NSDecimal ABI boundary --------------------
 *
 * NSDecimal is passed by value to and from code this framework does not own,
 * so the fields have to be filled the way the caller reads them: exponent as a
 * signed byte, length as the count of significant little-endian base-65536
 * words, zero length meaning "not a number" (see NSDecimal.h for the measured
 * layout).
 */
static NSDecimal NSDecimalFromValue(NSDecimalValue value) {
   NSDecimal out;
   uint64_t magnitude = value.mantissa;
   int length = 0;

   memset(&out, 0, sizeof(out));
   if(value.isNaN) {
    /* length 0 is the ABI's not-a-number. */
    return out;
   }
   for(int i = 0; i < 8; i++) {
    unsigned short word = (unsigned short)(magnitude & 0xFFFF);
    out._mantissa[i] = word;
    if(word != 0)
     length = i + 1;
    magnitude >>= 16;
   }
   out._length = length;
   out._exponent = value.exponent;
   out._isNegative = (value.isNegative && value.mantissa != 0) ? 1 : 0;
   out._isCompact = 1;
   return out;
}

static NSDecimalValue NSDecimalValueFromDecimal(NSDecimal decimal) {
   NSDecimalValue out = NSDecimalValueZero;
   __int128 magnitude = 0;
   unsigned length = decimal._length;
   int16_t exponent = decimal._exponent;

   if(length == 0) {
    out.isNaN = 1;
    return out;
   }
   if(length > 8)
    length = 8;

   for(int i = (int)length - 1; i >= 0; i--)
    magnitude = (magnitude << 16) | (unsigned short)decimal._mantissa[i];

   /* The wider ABI can hold 128 bits; this representation holds 64, so drop
    * the least significant digit repeatedly (rounding half away from zero)
    * until it fits.  Only the low digits are lost, never the magnitude. */
   while(magnitude > (__int128)UINT64_MAX) {
    __int128 quotient = magnitude / 10;
    if(magnitude - quotient * 10 >= 5)
     quotient++;
    magnitude = quotient;
    exponent++;
   }

   out.mantissa = (uint64_t)magnitude;
   out.exponent = exponent;
   out.isNegative = (decimal._isNegative && magnitude != 0) ? 1 : 0;
   return out;
}

@interface NSDecimalNumber (RavynInternal)
- initWithValue:(NSDecimalValue)value;
- (NSDecimalValue)_value;
+ (NSDecimalNumber *)decimalNumberWithValue:(NSDecimalValue)value;
@end

@implementation NSDecimalNumber

-(NSDecimalValue)_value {
   return _decimal;
}

-initWithValue:(NSDecimalValue)value {
   self=[self init];
   if(self != nil)
    _decimal=value;
   return self;
}

+ (NSDecimalNumber *)decimalNumberWithValue:(NSDecimalValue)value {
   return [[[self alloc] initWithValue:value] autorelease];
}

-initWithDecimal:(NSDecimal)decimal {
   _decimal=NSDecimalValueFromDecimal(decimal);
   return self;
}

-initWithMantissa:(uint64_t)mantissa exponent:(int16_t)exponent isNegative:(BOOL)flag {
   _decimal=NSDecimalMake(mantissa,exponent,flag);
   return self;
}

-initWithString:(NSString *)string {
   return [self initWithString:string locale:nil];
}

-initWithString:(NSString *)string locale:(NSDictionary *)locale {
   NSDecimalValue decimal;

   if(!NSDecimalFromString(string,&decimal)){
    [self dealloc];
    return nil;
   }

   return [self initWithValue:decimal];
}

-(void)dealloc {
   [super dealloc];
}

+(NSDecimalNumber *)decimalNumberWithDecimal:(NSDecimal)decimal {
   return [[[self alloc] initWithDecimal:decimal] autorelease];
}

+(NSDecimalNumber *)decimalNumberWithMantissa:(uint64_t)mantissa exponent:(int16_t)exponent isNegative:(BOOL)negative {
   return [[[self alloc] initWithMantissa:mantissa exponent:exponent isNegative:negative] autorelease];
}

+(NSDecimalNumber *)decimalNumberWithString:(NSString *)string {
   return [[[self alloc] initWithString:string] autorelease];
}

+(NSDecimalNumber *)decimalNumberWithString:(NSString *)string locale:(NSDictionary *)locale {
   return [[[self alloc] initWithString:string locale:locale] autorelease];
}

+(NSDecimalNumber *)zero {
   return [self decimalNumberWithValue:NSDecimalValueZero];
}

+(NSDecimalNumber *)one {
   return [self decimalNumberWithMantissa:1 exponent:0 isNegative:NO];
}

+(NSDecimalNumber *)minimumDecimalNumber {
   return [self decimalNumberWithMantissa:UINT64_MAX exponent:-128 isNegative:YES];
}

+(NSDecimalNumber *)maximumDecimalNumber {
   return [self decimalNumberWithMantissa:UINT64_MAX exponent:127 isNegative:NO];
}

+(NSDecimalNumber *)notANumber {
   return [self decimalNumberWithValue:NSDecimalMakeNaN()];
}

+(id <NSDecimalNumberBehaviors>)defaultBehavior {
   return nil;
}

+(void)setDefaultBehavior:(id <NSDecimalNumberBehaviors>)behavior {
   /* Rounding behaviors are not implemented; callers get the default
    * (round half away from zero on rescale) regardless. */
}

-(NSDecimal)decimalValue {
   return NSDecimalFromValue(_decimal);
}

-(double)doubleValue {
   double magnitude=(double)_decimal.mantissa*pow(10.0,(double)_decimal.exponent);

   return _decimal.isNegative?-magnitude:magnitude;
}

-(const char *)objCType {
   return @encode(double);
}

-(NSComparisonResult)compare:(NSNumber *)other {
   NSDecimalValue a=_decimal,b;
   int16_t exponent;
   __int128 va,vb,difference;

   if([other isKindOfClass:[NSDecimalNumber class]])
    b=[(NSDecimalNumber *)other _value];
   else
    b=[[NSDecimalNumber decimalNumberWithString:[other stringValue]] _value];

   if(a.isNaN || b.isNaN)
    return NSOrderedSame;

   exponent=(a.exponent<b.exponent)?a.exponent:b.exponent;
   if((int)(a.exponent-exponent)>NSDecimalScaleLimit)
    exponent=a.exponent-NSDecimalScaleLimit;
   if((int)(b.exponent-exponent)>NSDecimalScaleLimit)
    exponent=b.exponent-NSDecimalScaleLimit;

   va=NSDecimalScaledMantissa(a,exponent);
   vb=NSDecimalScaledMantissa(b,exponent);

   if(a.isNegative)
    va=-va;
   if(b.isNegative)
    vb=-vb;

   difference=va-vb;

   if(difference<0)
    return NSOrderedAscending;
   if(difference>0)
    return NSOrderedDescending;
   return NSOrderedSame;
}

-(BOOL)isEqualToNumber:(NSNumber *)other {
   if(self==other)
    return YES;

   return [self compare:other]==NSOrderedSame;
}

-(NSDecimalNumber *)decimalNumberByRoundingAccordingToBehavior:(id <NSDecimalNumberBehaviors>)behavior {
   return [[self copy] autorelease];
}

-(NSDecimalNumber *)decimalNumberByAdding:(NSDecimalNumber *)other {
   return [self decimalNumberByAdding:other withBehavior:nil];
}

-(NSDecimalNumber *)decimalNumberByAdding:(NSDecimalNumber *)other withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
   return [NSDecimalNumber decimalNumberWithValue:NSDecimalAdd(_decimal,[other _value])];
}

-(NSDecimalNumber *)decimalNumberBySubtracting:(NSDecimalNumber *)other {
   return [self decimalNumberBySubtracting:other withBehavior:nil];
}

-(NSDecimalNumber *)decimalNumberBySubtracting:(NSDecimalNumber *)other withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
   return [NSDecimalNumber decimalNumberWithValue:NSDecimalSubtract(_decimal,[other _value])];
}

-(NSDecimalNumber *)decimalNumberByMultiplyingBy:(NSDecimalNumber *)other {
   return [self decimalNumberByMultiplyingBy:other withBehavior:nil];
}

-(NSDecimalNumber *)decimalNumberByMultiplyingBy:(NSDecimalNumber *)other withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
   return [NSDecimalNumber decimalNumberWithValue:NSDecimalMultiply(_decimal,[other _value])];
}

-(NSDecimalNumber *)decimalNumberByDividingBy:(NSDecimalNumber *)other {
   return [self decimalNumberByDividingBy:other withBehavior:nil];
}

-(NSDecimalNumber *)decimalNumberByDividingBy:(NSDecimalNumber *)other withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
   return [NSDecimalNumber decimalNumberWithValue:NSDecimalDivide(_decimal,[other _value],self,_cmd)];
}

-(NSDecimalNumber *)decimalNumberByMultiplyingByPowerOf10:(int16_t)power {
   return [self decimalNumberByMultiplyingByPowerOf10:power withBehavior:nil];
}

-(NSDecimalNumber *)decimalNumberByMultiplyingByPowerOf10:(int16_t)power withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
   NSDecimalValue result=_decimal;
   long exponent=(long)result.exponent+power;

   if(result.isNaN)
    return self;
   if(result.mantissa==0)
    return [NSDecimalNumber zero];

   if(exponent>INT16_MAX || exponent<INT16_MIN)
    [NSException raise:NSDecimalNumberOverflowException
                format:@"-[%@ %s] exponent overflow",[self class],sel_getName(_cmd)];

   result.exponent=(int16_t)exponent;
   return [NSDecimalNumber decimalNumberWithValue:result];
}

-(NSDecimalNumber *)decimalNumberByRaisingToPower:(NSUInteger)power {
   return [self decimalNumberByRaisingToPower:power withBehavior:nil];
}

-(NSDecimalNumber *)decimalNumberByRaisingToPower:(NSUInteger)power withBehavior:(id <NSDecimalNumberBehaviors>)behavior {
   NSDecimalValue result=NSDecimalMake(1,0,NO);
   NSDecimalValue base=_decimal;
   NSUInteger i;

   if(base.isNaN)
    return self;
   if(power==0)
    return [NSDecimalNumber one];

   for(i=0;i<power;i++)
    result=NSDecimalMultiply(result,base);

   return [NSDecimalNumber decimalNumberWithValue:result];
}

-(NSString *)descriptionWithLocale:(NSDictionary *)locale {
   char digits[32];
   int length,point,i;
   NSMutableString *result=[NSMutableString string];

   if(_decimal.isNaN)
    return @"NaN";

   if(_decimal.mantissa==0)
    return @"0";

   snprintf(digits,sizeof(digits),"%llu",(unsigned long long)_decimal.mantissa);
   length=(int)strlen(digits);

   if(_decimal.isNegative)
    [result appendString:@"-"];

   if(_decimal.exponent>=0){
    [result appendString:[NSString stringWithUTF8String:digits]];
    for(i=0;i<_decimal.exponent;i++)
     [result appendString:@"0"];
   }
   else {
    point=length+_decimal.exponent;

    if(point>0){
     char head[32];

     memcpy(head,digits,(size_t)point);
     head[point]='\0';
     [result appendString:[NSString stringWithUTF8String:head]];
     [result appendString:@"."];
     [result appendString:[NSString stringWithUTF8String:digits+point]];
    }
    else {
     [result appendString:@"0."];
     for(i=0;i<-point;i++)
      [result appendString:@"0"];
     [result appendString:[NSString stringWithUTF8String:digits]];
    }

    /* Drop trailing fractional zeros: 2.50 is 2.5. */
    while([result length]>0 && [result characterAtIndex:[result length]-1]=='0')
     [result deleteCharactersInRange:NSMakeRange([result length]-1,1)];
    if([result length]>0 && [result characterAtIndex:[result length]-1]=='.')
     [result deleteCharactersInRange:NSMakeRange([result length]-1,1)];
   }

   return result;
}

@end
