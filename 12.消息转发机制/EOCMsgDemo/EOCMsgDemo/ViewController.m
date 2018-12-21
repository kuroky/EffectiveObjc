//
//  ViewController.m
//  EOCMsgDemo
//
//  Created by kuroky on 2018/12/6.
//  Copyright © 2018 Kuroky. All rights reserved.
//

#import "ViewController.h"
#import <objc/runtime.h>
#import "NSString+MXAdd.h"

struct TestCase {
    void *isa;
};

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    EOCAutoDictionary *obj = [EOCAutoDictionary new];
    //obj.date = [NSDate dateWithTimeIntervalSince1970:475372800];
    [obj test];
    //NSLog(@"%@", obj.date);
    
    [self methodChange];
    
    Spark *spark = [Spark new];
    [spark speak];
    
    struct TestCase *testcase = (__bridge void *)spark;
    testcase->isa = (__bridge void *)[Spark1 class];
    [spark speak];
}

- (void)test {
    NSLog(@"ViewController");
}

- (void)methodChange {
    NSString *str1 = @"AbCdEfG";
    NSLog(@"lowercaseString: %@", str1.lowercaseString);
    
    [str1 mx_myCapitalizedString];    
}

@end

@implementation Spark

- (void)speak {
    NSLog(@"speak");
}

@end

@implementation Spark1

- (void)speak {
    NSLog(@"speak1");
}

@end

@interface EOCAutoDictionary ()

@property (nonatomic, strong) NSMutableDictionary *backingStore;
@property (nonatomic, strong) ViewController *viewController;

@end

@implementation EOCAutoDictionary

@dynamic date;

- (id)init {
    if (self = [super init]) {
        _backingStore = [NSMutableDictionary new];
        self.viewController = [ViewController new];
    }
    return self;
}

// 第一步 如果没有实现test方法
+ (BOOL)resolveInstanceMethod:(SEL)sel {
    NSString *selectorString = NSStringFromSelector(sel);
    if ([selectorString isEqualToString:@"test"]) {
        //class_addMethod([self class], sel, (IMP)autoTest, "v@:");
        return [super resolveInstanceMethod:sel];
    }
    else if ([selectorString hasPrefix:@"set"]) {
        class_addMethod([self class], sel, (IMP)autoDictonarySetter, "v@:@");
    }
    else if ([selectorString isEqualToString:@"date"]) {
        class_addMethod([self class], sel, (IMP)autoDictionaryGetter, "@@:");
    }
    
    return [super resolveInstanceMethod:sel];
}


id autoDictionaryGetter(id self, SEL _cmd) {
    // get the backing store from the object
    EOCAutoDictionary *typeSelf = (EOCAutoDictionary *)self;
    NSMutableDictionary *backingStore = typeSelf.backingStore;
    
    // the key is simply the selector name
    NSString *key = NSStringFromSelector(_cmd);
    
    // return the value
    return [backingStore objectForKey:key];
}

void autoDictonarySetter(id self, SEL _cmd, id value) {
    // get the backing store from the object
    EOCAutoDictionary *typeSelf = (EOCAutoDictionary *)self;
    NSMutableDictionary *backingStore = typeSelf.backingStore;
    
    /* the selector will be for example, "setOpaqueObject:".
     we need to remove the "set", ":" and lowercase the first
     letter of the remainder.
     */
    NSString *selectorString = NSStringFromSelector(_cmd);
    NSMutableString *key = [selectorString mutableCopy];
    
    // remove the ':' at the end
    [key deleteCharactersInRange:NSMakeRange(key.length - 1, 1)];
    
    // remove the 'set' prefix
    [key deleteCharactersInRange:NSMakeRange(0, 3)];
    
    // lowercase the first character
    NSString *lowercaseFirstChar = [[key substringToIndex:1] lowercaseString];
    [key replaceCharactersInRange:NSMakeRange(0, 1) withString:lowercaseFirstChar];
    
    if (value) {
        [backingStore setObject:value forKey:key];
    }
    else {
        [backingStore removeObjectForKey:key];
    }
}

// 第二步 尝试找到一个能响应该消息的对象。如果获取到，则直接转发给它。如果返回了nil，继续下面的动作
- (id)forwardingTargetForSelector:(SEL)aSelector {
    NSString *selectorString = NSStringFromSelector(aSelector);
    if ([selectorString isEqualToString:@"test"]) {
        //return self.viewController;
        return nil;
    }
    return [super forwardingTargetForSelector:aSelector];
}

// 第三步 1.尝试获得一个方法签名。如果获取不到，则直接调用doesNotRecognizeSelector抛出异常
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    NSMethodSignature *signature = [super methodSignatureForSelector:aSelector];
    if (!signature) {
        if ([ViewController instancesRespondToSelector:aSelector]) {
            signature = [self.viewController methodSignatureForSelector:aSelector];
        }
    }
    return signature;
}

// 第三步 2 异常
- (void)doesNotRecognizeSelector:(SEL)aSelector {
    
}

// 第三步 2. 将地1获取到的方法签名包装成Invocation传入，如何处理就在这里面。
- (void)forwardInvocation:(NSInvocation *)anInvocation {
    if ([ViewController instanceMethodSignatureForSelector:anInvocation.selector]) {
        [anInvocation invokeWithTarget:[ViewController new]];
    }
}


@end
