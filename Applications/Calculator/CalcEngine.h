#import <Foundation/Foundation.h>

typedef enum { CalcModeStandard = 0, CalcModeScientific = 1, CalcModeProgrammer = 2 } CalcMode;
typedef enum { AngleDegrees = 0, AngleRadians = 1 } AngleMode;
typedef enum { WordSize64 = 0, WordSize32 = 1, WordSize16 = 2, WordSize8 = 3 } WordSize;

@interface CalcEngine : NSObject

@property (nonatomic, assign) CalcMode mode;
@property (nonatomic, assign) AngleMode angleMode;
@property (nonatomic, assign) WordSize wordSize;
@property (nonatomic, assign) int inputBase;

@property (nonatomic, copy) NSString *display;
@property (nonatomic, readonly) NSString *expression;

@property (nonatomic, assign) double memory;
@property (nonatomic, assign) unsigned long long progMemory;
@property (nonatomic, assign) unsigned long long progValue;

// Standard / Scientific entry
- (void)clear;
- (void)clearEntry;
- (void)inputDigit:(int)d;
- (void)inputDecimalPoint;
- (void)inputOperator:(NSString *)op;
- (void)inputEquals;
- (void)inputOpenParen;
- (void)inputCloseParen;
- (void)inputFunction:(NSString *)fn;
- (void)inputConstant:(NSString *)name;
- (void)inputEE;
- (void)deleteLastDigit;
- (void)toggleSign;
- (void)percent;
- (unsigned long long)wordMask;
- (BOOL)progEntering;
- (void)setProgEntering:(BOOL)v;
- (NSMutableString *)progEntry;

// Memory
- (void)inputPastedString:(NSString *)s;
- (void)memoryClear;
- (void)memoryRecall;
- (void)memoryAdd;
- (void)memorySubtract;

// Programmer
- (void)inputProgrammerDigit:(int)d;
- (void)inputProgrammerOperator:(NSString *)op;
- (void)inputProgrammerEquals;
- (void)setBit:(int)bit value:(BOOL)v;

// Readouts
- (NSString *)hexReadout;
- (NSString *)decReadout;
- (NSString *)octReadout;
- (NSString *)binReadout;

// Tape
- (NSString *)lastTapeLine;

@end