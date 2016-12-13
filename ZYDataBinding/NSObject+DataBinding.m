//
//  NSObject+DataBinding.m
//  ZYDataBinding
//
//  Created by zhangyun on 13/12/2016.
//  Copyright © 2016 zhangyun. All rights reserved.
//

#import "NSObject+DataBinding.h"
#import <objc/runtime.h>
#import <objc/message.h>


#pragma mark public keys
NSString *const kZYDBChangeKeyObject = @"kZYDBChangeKeyObject";
NSString *const kZYDBChanegKeyOld = @"kZYDBChanegKeyOld";
NSString *const kZYDBChangeKeyNew = @"kZYDBChangeKeyNew";
NSString *const kYZDBChangeKeyKeyPath = @"kYZDBChangeKeyKeyPath";

#pragma mark private change keys
static NSString *const kZYDBChangeKeyBoundKey = @"_ZYDBChangeKeyBoundKey";
static NSString *const kZYDBChangeKeyBindingTransformKey = @"_ZYDBChangeKeyBindingTransformKey";

static void* const kZYDBSwizzleDeallocKey = (void *)&kZYDBSwizzleDeallocKey;
//
static void* const kZYDBKVOContext = (void*)&kZYDBKVOContext;

// 判断对象是否存在
#define ZYDBNotNull(obj) ((obj) != nil && ![(obj) isEqual:[NSNull null]])


#pragma mark - ObserverContainer
@class _ZYDBObserver;
@interface ZYDBObserverContainer : NSObject
@property (nonatomic,strong) NSHashTable *observers;
- (void)addObserver:(_ZYDBObserver *)observer;
- (void)removeObserver:(_ZYDBObserver *)observer;
@end

#pragma mark - NSObject (RZDataBinding_Private)
// 这个分类用来保存，object的观察者
@interface NSObject (ZYDataBding_Private)
- (NSMutableArray *)zy_registeredObservers;
- (void)zy_setRegisteredObservers:(NSMutableArray *)registeredObservers;

- (ZYDBObserverContainer *)zy_dependentObservers;
-(void)zy_setDependentObservers:(ZYDBObserverContainer *)dependentObservers;

- (void)zy_addTarget:(id)target action:(SEL)action boundKey:(NSString *)boundKey bindingTransform:(ZYDBKeyBindingTransform)bindingTransform forKeyPath:(NSString *)keyPath withOPtions:(NSKeyValueObservingOptions)options;

@end

#pragma mark - _ZYDBObserver
@interface _ZYDBObserver : NSObject
@property (nonatomic,weak) NSObject *observedObject;
@property (nonatomic,copy) NSString *keyPath;
@property (nonatomic,copy) NSString *boundKey;
@property (nonatomic,assign) NSKeyValueObservingOptions  options;

@property (nonatomic,weak) id  target;
@property (nonatomic,assign) SEL  action;
@property (nonatomic,strong) NSMethodSignature *methodSignature;
@property (nonatomic,copy) ZYDBKeyBindingTransform bindingTransform;
@end

#pragma mark - ZYDBObserverContainer IMP
@implementation ZYDBObserverContainer

- (instancetype)init{
    self = [super init];
    if (nil != self) {
        _observers = [NSHashTable weakObjectsHashTable];
    }
    return self;
}

- (void)addObserver:(_ZYDBObserver *)observer{
    @synchronized (self) {
        [self.observers addObject:observer];
    }
}

- (void)removeObserver:(_ZYDBObserver *)observer{
    @synchronized (self) {
        [self.observers removeObject:observer];
    }
}
@end

#pragma mark - _ZYDBObserver IMP
@implementation _ZYDBObserver

- (instancetype)initWithObserveredObject:(NSObject *)observeredObject keyPath:(NSString *)keypath observationOptions:(NSKeyValueObservingOptions)options{
    self = [super init];
    if (self != nil) {
        _observedObject = observeredObject;
        _keyPath = keypath;
        _options = options;
    }
    return self;
}

- (void)setTarget:(id)target action:(SEL)action boundKey:(NSString *)boundKey bindingTransform:(ZYDBKeyBindingTransform)bindingTransform{
    
    self.target = target;
    self.action = action;
    self.methodSignature = [target methodSignatureForSelector:action];
    
    self.boundKey = boundKey;
    self.bindingTransform = bindingTransform;
    
    [self.observedObject addObserver:self forKeyPath:self.keyPath options:self.options context:kZYDBKVOContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context{
    
    if (context == kZYDBKVOContext) {
        if (self.methodSignature.numberOfArguments > 2) {
            NSDictionary *changeDict = [self changeDictForKVOChange:change];
            
            ((void(*)(id,SEL,NSDictionary *))objc_msgSend)(self.target,self.action,changeDict);
        }
    }else{
        ((void(*)(id,SEL))objc_msgSend)(self.target,self.action);
    }
}

- (NSDictionary *)changeDictForKVOChange:(NSDictionary *)change{
    
    NSMutableDictionary *changeDict = [NSMutableDictionary dictionary];
    
    if (nil != self.observedObject) {
        changeDict[kZYDBChangeKeyObject] = self.observedObject;
    }
    
    if (ZYDBNotNull(change[NSKeyValueChangeOldKey])) {
        changeDict[kZYDBChanegKeyOld] = change[NSKeyValueChangeOldKey];
    }
    
    if (ZYDBNotNull(change[NSKeyValueChangeNewKey])) {
        changeDict[kZYDBChangeKeyNew] = change[NSKeyValueChangeNewKey];
    }
    
    if (self.keyPath) {
        changeDict[kYZDBChangeKeyKeyPath] = self.keyPath;
    }
    
    if (self.boundKey) {
        changeDict[kZYDBChangeKeyBoundKey] = self.boundKey;
    }
    
    if (self.bindingTransform) {
        changeDict[kZYDBChangeKeyBindingTransformKey] = self.bindingTransform;
    }
    return [changeDict copy];
}

- (void)invalidate{
    
    [[self.target zy_dependentObservers] removeObserver:self];
    [[self.observedObject zy_registeredObservers] removeObject:self];
    
    
    @try {
        [self.observedObject removeObserver:self forKeyPath:self.keyPath context:kZYDBKVOContext];
    } @catch (NSException *exception) {
        ZYDBLog(@"ZYDB attempted to remove an observer from object %@,but the observer was never added.",self.observedObject);
    }
    
    self.observedObject = nil;
    self.target = nil;
    self.action = NULL;
    self.methodSignature = nil;
}
@end

#pragma mark - ZYDataBding_Private IMP

@implementation NSObject (ZYDataBding_Private)

- (NSMutableArray *)zy_registeredObservers{
    return objc_getAssociatedObject(self, @selector(zy_registeredObservers));
}

- (void)zy_setRegisteredObservers:(NSMutableArray *)registeredObservers{
    objc_setAssociatedObject(self, @selector(zy_registeredObservers), registeredObservers,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (ZYDBObserverContainer *)zy_dependentObservers{
    return  objc_getAssociatedObject(self, @selector(zy_dependentObservers));
}

- (void)zy_setDependentObservers:(ZYDBObserverContainer *)dependentObservers{
    objc_setAssociatedObject(self, @selector(zy_dependentObservers), dependentObservers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)zy_addTarget:(id)target action:(SEL)action boundKey:(NSString *)boundKey bindingTransform:(ZYDBKeyBindingTransform)bindingTransform forKeyPath:(NSString *)keyPath withOPtions:(NSKeyValueObservingOptions)options{
 
    NSMutableArray *registeredObservers = nil;
    ZYDBObserverContainer *dependentObservers = nil;
    
    _ZYDBObserver *observer = [[_ZYDBObserver alloc] initWithObserveredObject:self keyPath:keyPath observationOptions:options];
    [observer setTarget:target action:action boundKey:boundKey bindingTransform:bindingTransform];
    
    
    @synchronized (self) {
        registeredObservers = [self zy_registeredObservers];
        
        if (nil == registeredObservers) {
            registeredObservers = [NSMutableArray array];
            [self zy_setRegisteredObservers:registeredObservers];
        }
        [registeredObservers addObject:observer];
    }
    
    @synchronized (target) {
        
        dependentObservers = [target zy_dependentObservers];
        if (nil == dependentObservers) {
            dependentObservers = [ZYDBObserverContainer new];
            [target zy_setDependentObservers:dependentObservers];
        }
        [dependentObservers addObserver:observer];
    }
}

- (void)zy_cleanupObserver{
    NSMutableArray *registeredObservers = [self zy_registeredObservers];
    ZYDBObserverContainer *dependentObservers = [self zy_dependentObservers];
    
    [[registeredObservers copy] enumerateObjectsUsingBlock:^(_ZYDBObserver *obs, NSUInteger idx, BOOL * _Nonnull stop) {
        [obs invalidate];
    }];
    
    [[dependentObservers.observers allObjects] enumerateObjectsUsingBlock:^(_ZYDBObserver *obs, NSUInteger idx, BOOL * _Nonnull stop) {
        [obs invalidate];
    }];
}
@end

BOOL zy_rqeuiredDeallocSwizzle(Class class){
    
    BOOL swizzled = NO;
    for (Class currentClass = class; !swizzled && currentClass != nil; currentClass = class_getSuperclass(currentClass)) {
        swizzled  = [objc_getAssociatedObject(currentClass, kZYDBSwizzleDeallocKey) boolValue];
    }
    return !swizzled;
}

void zy_swizzleDeallocIfNeed(Class class){
    
    // 静态变量，并且用了once，表示只需要设置过一次
    static SEL deallocSEL = NULL;
    static SEL cleanupSEL = NULL;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        deallocSEL = sel_getUid("dealloc");
        cleanupSEL = sel_getUid("zy_cleanupObserver");
    });
    
    @synchronized (class) {
        if (!zy_rqeuiredDeallocSwizzle(class)) {
            return;
        }
        objc_setAssociatedObject(class, kZYDBSwizzleDeallocKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    Method dealloc = NULL;
    unsigned int n;
    Method *methods = class_copyMethodList(class, &n);
    for (unsigned int i = 0; i < n; i++) {
        if (method_getName(methods[i]) == deallocSEL) {
            dealloc = methods[i];
        }
    }
    free(methods);
    
    if (dealloc == NULL) {
        Class superclass = class_getSuperclass(class);
        class_addMethod(class, deallocSEL, imp_implementationWithBlock(^(__unsafe_unretained id self){
           
            ((void(*)(id,SEL))objc_msgSend)(self,cleanupSEL);
            
            struct objc_super superStruct = (struct objc_super){
             self,superclass
            };
            ((void(*)(struct objc_super*,SEL))objc_msgSend)(&superStruct,deallocSEL);
        
        }), method_getTypeEncoding(dealloc));
    }else{
       __block IMP deallocIMP = method_setImplementation(dealloc, imp_implementationWithBlock(^(__unsafe_unretained id self){
            ((void(*)(id,SEL))objc_msgSend)(self,cleanupSEL);
            
           ((void(*)(id,SEL))deallocIMP)(self,deallocSEL);
        }));
    }
}

#pragma mark - NSObject(DataBinding) IMP
@implementation NSObject(DataBinding)
- (void)zy_addTarget:(id)target action:(SEL)action forkeyPathChange:(NSString *)keyPath{
    [self zy_addTarget:target action:action forKeyPathChange:keyPath callImmediately:NO];
}

- (void)zy_addTarget:(id)target action:(SEL)action forKeyPathChange:(NSString *)keyPath callImmediately:(BOOL)callImmediately{
    NSParameterAssert(target);
    NSParameterAssert(keyPath);
    NSParameterAssert(action);
    
    NSKeyValueObservingOptions options = kNilOptions;
    // 如果参数大于2，就把新老值传递过去
    if ([target methodSignatureForSelector:action].numberOfArguments > 2) {
        options |= NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld;
    }
    
    if (callImmediately) { // 注册完成会立即调用一次
        options |= NSKeyValueObservingOptionInitial;
    }
    
    [self zy_addTarget:target action:action boundKey:nil bindingTransform:nil forKeyPath:keyPath withOPtions:options];
}

@end

#pragma mark -
