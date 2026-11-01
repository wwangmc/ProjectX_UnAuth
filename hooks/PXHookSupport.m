#import "PXHookSupport.h"
#import <substrate.h>

static NSMutableDictionary *PXOriginals;
static NSString *PXMethodKey(Class cls, SEL sel) {
    return [NSString stringWithFormat:@"%p:%s", cls, sel_getName(sel)];
}
BOOL PXInstallMethod(Class cls, SEL selector, IMP replacement, const char *returnType, unsigned arguments) {
    if (!cls || !selector) return NO;
    Method method=class_getInstanceMethod(cls,selector);
    if (!method || method_getNumberOfArguments(method)!=arguments) return NO;
    char type[128]={0}; method_getReturnType(method,type,sizeof(type));
    if (returnType && strcmp(type,returnType)) return NO;
    @synchronized (NSObject.class) {
        if (!PXOriginals) PXOriginals=[NSMutableDictionary dictionary];
        NSString *key=PXMethodKey(cls,selector);
        if (PXOriginals[key] || method_getImplementation(method)==replacement) return YES;
        IMP original=NULL;
        MSHookMessageEx(cls,selector,replacement,&original);
        if (original) PXOriginals[key]=[NSValue valueWithPointer:original];
        return original!=NULL;
    }
}
IMP PXOriginalMethod(id object, SEL selector) {
    @synchronized (NSObject.class) {
        for (Class cls=object_getClass(object); cls; cls=class_getSuperclass(cls)) {
            NSValue *value=PXOriginals[PXMethodKey(cls,selector)];
            if (value) return value.pointerValue;
        }
    }
    return NULL;
}
IMP PXOriginalForClass(Class cls, SEL selector) {
    @synchronized (NSObject.class) {
        return [PXOriginals[PXMethodKey(cls,selector)] pointerValue];
    }
}
