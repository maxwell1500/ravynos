/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSRaise.h>

#import <sys/param.h>
#include <string.h>
#import <objc/message.h>
#import <objc/runtime.h>


#ifdef HAVE_LIBFFI
#include <ffi.h>
#include <stdlib.h>

typedef struct NSFFIAllocation {
    void *pointer;
    struct NSFFIAllocation *next;
} NSFFIAllocation;

static void *NSFFIAllocate(NSFFIAllocation **list,size_t size) {
    void *pointer=calloc(1,size);
    NSFFIAllocation *node=malloc(sizeof(NSFFIAllocation));

    node->pointer=pointer;
    node->next=*list;
    *list=node;

    return pointer;
}

static void NSFFIFreeAllocations(NSFFIAllocation *list) {
    while(list!=NULL){
        NSFFIAllocation *next=list->next;

        free(list->pointer);
        free(list);
        list=next;
    }
}

static ffi_type *NSFFITypeForEncoding(const char *type,NSFFIAllocation **allocations);

static ffi_type *NSFFIBlobTypeForEncoding(const char *type,NSFFIAllocation **allocations) {
    NSUInteger size=0,alignment=0;

    NSGetSizeAndAlignment(type,&size,&alignment);

    if(size==0)
        return &ffi_type_pointer;

    ffi_type **elements=NSFFIAllocate(allocations,sizeof(ffi_type*)*(size+1));
    ffi_type *result=NSFFIAllocate(allocations,sizeof(ffi_type));
    NSUInteger i;

    for(i=0;i<size;i++)
        elements[i]=&ffi_type_uint8;
    elements[size]=NULL;

    result->size=0;
    result->alignment=0;
    result->type=FFI_TYPE_STRUCT;
    result->elements=elements;

    return result;
}

static ffi_type *NSFFIAggregateTypeForEncoding(const char *type,NSFFIAllocation **allocations) {
    NSUInteger capacity=8,count=0,size=0,alignment=0;
    ffi_type **elements=NSFFIAllocate(allocations,sizeof(ffi_type*)*(capacity+1));
    ffi_type *result=NSFFIAllocate(allocations,sizeof(ffi_type));
    const char *cursor=type+1;

    while(*cursor!='\0' && *cursor!='=' && *cursor!='}' && *cursor!=')')
        cursor++;

    if(*cursor=='=')
        cursor++;

    while(*cursor!='\0' && *cursor!='}' && *cursor!=')'){
        const char *next;

        if(count+1>=capacity){
            ffi_type **grown=NSFFIAllocate(allocations,sizeof(ffi_type*)*(capacity*2+1));

            memcpy(grown,elements,sizeof(ffi_type*)*(count+1));
            elements=grown;
            capacity*=2;
        }

        elements[count++]=NSFFITypeForEncoding(cursor,allocations);

        next=NSGetSizeAndAlignment(cursor,&size,&alignment);
        if(next==NULL || next<=cursor)
            break;
        cursor=next;
    }

    elements[count]=NULL;

    result->size=0;
    result->alignment=0;
    result->type=FFI_TYPE_STRUCT;
    result->elements=elements;

    return result;
}

static ffi_type *NSFFIArrayTypeForEncoding(const char *type,NSFFIAllocation **allocations) {
    const char *cursor=type+1;
    long count=0;
    ffi_type *element;
    ffi_type **elements;
    ffi_type *result;
    long i;

    while(*cursor>='0' && *cursor<='9'){
        count=count*10+(*cursor-'0');
        cursor++;
    }

    element=NSFFITypeForEncoding(cursor,allocations);
    elements=NSFFIAllocate(allocations,sizeof(ffi_type*)*(count+1));
    result=NSFFIAllocate(allocations,sizeof(ffi_type));

    for(i=0;i<count;i++)
        elements[i]=element;
    elements[count]=NULL;

    result->size=0;
    result->alignment=0;
    result->type=FFI_TYPE_STRUCT;
    result->elements=elements;

    return result;
}

static ffi_type *NSFFITypeForEncoding(const char *type,NSFFIAllocation **allocations) {
    while(*type=='r' || *type=='n' || *type=='N' || *type=='o' ||
          *type=='O' || *type=='R' || *type=='V')
        type++;

    switch(*type){
     case _C_VOID: return &ffi_type_void;
     case _C_CHR: return &ffi_type_sint8;
     case _C_UCHR: return &ffi_type_uint8;
     case _C_BOOL: return &ffi_type_uint8;
     case _C_SHT: return &ffi_type_sint16;
     case _C_USHT: return &ffi_type_uint16;
     case _C_INT: return &ffi_type_sint32;
     case _C_UINT: return &ffi_type_uint32;
     case _C_LNG: return &ffi_type_sint64;
     case _C_ULNG: return &ffi_type_uint64;
     case _C_LNG_LNG: return &ffi_type_sint64;
     case _C_ULNG_LNG: return &ffi_type_uint64;
     case _C_FLT: return &ffi_type_float;
     case _C_DBL: return &ffi_type_double;
     case 'D': return &ffi_type_longdouble;
     case _C_PTR: return &ffi_type_pointer;
     case _C_CHARPTR: return &ffi_type_pointer;
     case _C_ATOM: return &ffi_type_pointer;
     case _C_ID: return &ffi_type_pointer;
     case _C_CLASS: return &ffi_type_pointer;
     case _C_SEL: return &ffi_type_pointer;
     case _C_STRUCT_B: return NSFFIAggregateTypeForEncoding(type,allocations);
     case _C_UNION_B: return NSFFIBlobTypeForEncoding(type,allocations);
     case _C_ARY_B: return NSFFIArrayTypeForEncoding(type,allocations);
     default: return NSFFIBlobTypeForEncoding(type,allocations);
    }
}
#endif /* HAVE_LIBFFI */

@implementation NSInvocation

-(void)buildFrame {
   NSInteger  i,count=[_signature numberOfArguments];
   NSUInteger align;

   NSGetSizeAndAlignment([_signature methodReturnType],&_returnSize,&align);
   _returnValue=NSZoneCalloc(NULL,MAX(_returnSize, sizeof(NSUInteger)),1);

   _argumentFrameSize=0;
   _argumentSizes=NSZoneCalloc(NULL,count,sizeof(NSUInteger));
   _argumentOffsets=NSZoneCalloc(NULL,count,sizeof(NSUInteger));

   for(i=0;i<count;i++){
    NSUInteger naturalSize;
    NSUInteger promotedSize;

    _argumentOffsets[i]=_argumentFrameSize;

    NSGetSizeAndAlignment([_signature getArgumentTypeAtIndex:i],&naturalSize,&align);
    promotedSize=((naturalSize+sizeof(NSUInteger)-1)/sizeof(NSUInteger))*sizeof(NSUInteger);

    _argumentSizes[i]=naturalSize;
    _argumentFrameSize+=promotedSize;
   }
}

-initWithMethodSignature:(NSMethodSignature *)signature {
   if(signature==nil){
    [self dealloc];
    [NSException raise:NSInvalidArgumentException format:@"nil signature in NSInvocation creation"];
    return nil;
   }

   _signature=[signature retain];

   [self buildFrame];

   _argumentFrame=NSZoneCalloc(NULL,_argumentFrameSize,1);

   return self;
}

-initWithMethodSignature:(NSMethodSignature *)signature arguments:(void *)arguments {
   unsigned       i;
   uint8_t *stackFrame=arguments;

   [self initWithMethodSignature:signature];

   for(i=0;i<_argumentFrameSize;i++)
    _argumentFrame[i]=stackFrame[i];

   return self;
}

-(void)dealloc {
    if (_retainArguments) {
        NSInteger i, count = [_signature numberOfArguments];

        for (i = 0; i < count; ++i) {
            const char *type = [_signature getArgumentTypeAtIndex:i];

            switch (type[0]) {
                case '@': {
                    id object;

                    [self getArgument:&object atIndex:i];
                    [object release];
                    break;
                }

                case '*': {
                    char *ptr;

                    [self getArgument:&ptr atIndex:i];
                    NSZoneFree(NULL, ptr);
                    break;
                }

                default:
                    break;
            }
        }
    }

   NSZoneFree(NULL,_returnValue);
   NSZoneFree(NULL,_argumentSizes);
   NSZoneFree(NULL,_argumentOffsets);
   NSZoneFree(NULL,_argumentFrame);
   [_signature release];
   NSDeallocateObject(self);
   return;
   [super dealloc];
}

static void *bufferForType(void *buffer,const char *type){
   NSUInteger size,align;

   NSGetSizeAndAlignment(type,&size,&align);
   if(buffer!=NULL)
    NSZoneFree(NULL,buffer);

   return NSZoneMalloc(NULL,size);
}

-initWithCoder:(NSCoder *)coder {
   const char *type;
   NSInteger         i,count;
   void       *buffer=NULL;

   _signature=[[coder decodeObject] retain];

   [self buildFrame];

   _argumentFrame=NSZoneCalloc(NULL,_argumentFrameSize,1);

   if([_signature methodReturnLength]>0){
    type=[_signature methodReturnType];
    buffer=bufferForType(buffer,type);
    [coder decodeValueOfObjCType:type at:buffer];
    [self setReturnValue:buffer];
   }

   count=[_signature numberOfArguments];
   for(i=0;i<count;i++){
    type=[_signature getArgumentTypeAtIndex:i];
    buffer=bufferForType(buffer,type);
    [coder decodeValueOfObjCType:type at:buffer];
    [self setArgument:buffer atIndex:i];
   }
   NSZoneFree(NULL,buffer);

   return self;
}

-(void)encodeWithCoder:(NSCoder *)coder {
   const char *type;
   NSInteger         i,count;
   void       *buffer=NULL;

   [coder encodeObject:_signature];

   if([_signature methodReturnLength]>0){
    type=[_signature methodReturnType];
    buffer=bufferForType(buffer,type);
    [self getReturnValue:buffer];
    [coder encodeValueOfObjCType:type at:buffer];
   }

   count=[_signature numberOfArguments];
   for(i=0;i<count;i++){
    type=[_signature getArgumentTypeAtIndex:i];
    buffer=bufferForType(buffer,type);
    [self getArgument:buffer atIndex:i];
    [coder encodeValueOfObjCType:type at:buffer];
   }
}

+(NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)signature {
   return [[[self allocWithZone:NULL] initWithMethodSignature:signature] autorelease];
}

+(NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)signature arguments:(void *)arguments {
   return [[[self allocWithZone:NULL] initWithMethodSignature:signature arguments:arguments] autorelease];
}

-(NSMethodSignature *)methodSignature {
   return _signature;
}

static void byteCopy(void *src,void *dst,NSUInteger length){
   NSInteger i;

   for(i=0;i<length;i++)
    ((char *)dst)[i]=((char *)src)[i];
}

-(void)getReturnValue:(void *)pointerToValue {
   byteCopy(_returnValue,pointerToValue,_returnSize);
}

-(void)setReturnValue:(void *)pointerToValue {
   byteCopy(pointerToValue,_returnValue,_returnSize);
}


-(void)getArgument:(void *)pointerToValue atIndex:(NSInteger)index
{
    NSUInteger naturalSize = _argumentSizes[index];
    NSUInteger promotedSize = ((naturalSize + sizeof(NSUInteger) - 1) / sizeof(NSUInteger)) * sizeof(NSUInteger);

    if (naturalSize == promotedSize) {
        byteCopy(_argumentFrame + _argumentOffsets[index], pointerToValue, naturalSize);
    } else if (promotedSize == sizeof(long)) {
        long promoted;

        byteCopy(_argumentFrame + _argumentOffsets[index], &promoted, promotedSize);
        if (naturalSize == 1) {
            *((char *)pointerToValue) = (char)promoted;
        } else if (naturalSize == 2) {
            *((short *)pointerToValue) = (short)promoted;
        } else if (naturalSize == 4) {
            *((int32_t *)pointerToValue) = (int32_t)promoted;
        }
    } else {
        [NSException raise:NSInvalidArgumentException format:@"Unable to convert naturalSize=%d to promotedSize=%d", naturalSize, promotedSize];
    }
}


- (void)setArgument:(void *)pointerToValue atIndex:(NSInteger)index
{
    NSUInteger naturalSize = _argumentSizes[index];
    NSUInteger promotedSize = ((naturalSize + sizeof(NSUInteger) - 1) / sizeof(NSUInteger)) * sizeof(NSUInteger);

    if (naturalSize == promotedSize) {
        byteCopy(pointerToValue, _argumentFrame + _argumentOffsets[index], naturalSize);
    } else if (promotedSize == sizeof(long)) {
        long promoted;

        if (naturalSize == 1) {
            promoted = *((char *)pointerToValue);
        } else if (naturalSize == 2) {
            promoted = *((short *)pointerToValue);
        } else if (naturalSize == 4) {
            promoted = *((int32_t *)pointerToValue);
        }

        byteCopy(&promoted, _argumentFrame + _argumentOffsets[index], promotedSize);
    } else {
        [NSException raise:NSInvalidArgumentException format:@"Unable to convert naturalSize=%ld to promotedSize=%ld", naturalSize, promotedSize];
    }
}


-(void)retainArguments {
    if (!_retainArguments) {
        NSInteger i, count = [_signature numberOfArguments];

        _retainArguments=YES;
        for (i = 0; i < count; ++i) {
            const char *type = [_signature getArgumentTypeAtIndex:i];

            switch (type[0]) {
                case '@': {
                    id object;

                    [self getArgument:&object atIndex:i];
                    [object retain];
                    break;
                }

                case '*': {
                    char *ptr, *copy, length;

                    [self getArgument:&ptr atIndex:i];
                    length = strlen(ptr);
                    copy = NSZoneCalloc(NULL, length+1, 1);
                    byteCopy(ptr, copy, length);
                    [self setArgument:&copy atIndex:i];
                    break;
                }

                default:
                    break;
            }
        }
    }
}

-(BOOL)argumentsRetained {
   return _retainArguments;
}

-(SEL)selector {
   SEL result;

   [self getArgument:&result atIndex:1];

   return result;
}

-(void)setSelector:(SEL)selector {
   [self setArgument:&selector atIndex:1];
}

-target {
   id result;

   [self getArgument:&result atIndex:0];

   return result;
}

-(void)setTarget:target {
   [self setArgument:&target atIndex:0];
}


- (void)invokeWithTarget:target
{
    [self setTarget: target];
    [self invoke];
}


- (void)invoke
{
#ifdef HAVE_LIBFFI
    NSMethodSignature *signature=_signature;
    NSUInteger argumentCount=[signature numberOfArguments];
    NSFFIAllocation *allocations=NULL;
    ffi_type *returnType=NSFFITypeForEncoding([signature methodReturnType],&allocations);
    ffi_type *argumentTypes[argumentCount];
    void     *argumentValues[argumentCount];
    ffi_cif   cif;
    NSUInteger i;

    for(i=0;i<argumentCount;i++){
        argumentTypes[i]=NSFFITypeForEncoding([signature getArgumentTypeAtIndex:i],&allocations);
        argumentValues[i]=_argumentFrame+_argumentOffsets[i];
    }

    if(ffi_prep_cif(&cif,FFI_DEFAULT_ABI,(unsigned)argumentCount,returnType,argumentTypes)!=FFI_OK){
        NSFFIFreeAllocations(allocations);
        [NSException raise:NSInvalidArgumentException
                    format:@"-[NSInvocation invoke] cannot build a call frame for %@",signature];
        return;
    }

    {
        id target=[self target];
        IMP imp=class_getMethodImplementation(object_getClass(target),[self selector]);

        ffi_call(&cif,FFI_FN(imp),_returnValue,argumentValues);
    }

    NSFFIFreeAllocations(allocations);
#else
    NSInvalidAbstractInvocation();
#endif
}


-(id)description
{
   return [NSString stringWithFormat:@"<%@ with signature %@>", [super description], [_signature description]];
}

@end
