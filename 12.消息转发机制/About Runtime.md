# About Runtime
## 简介
RunTime简称运行时。OC就是运行时机制，对于OC的函数，属于动态调用过程，在编译的时候并不能决定真正调用哪个函数，只有在真正运行的时候才会根据函数的名称找到对应的函数来调用。
	在编译阶段，OC可以调用任何函数，即使这个函数并未实现，只要声明过就不会报错。
## Runtime作用
### 1.发送消息
在编译时，Objective-C函数调用的语法都被翻译成C的函数调用*-objc_msgSend()*.

```
[array insertObject:foo atIndex:5];

objc_msgSend(array, @selector(insertObject:atIndex:), foo, 5);
```
在Objective-C中，类、对象、方法都是C的结构体，在*objc/objc.h*源文件

```
struct objc_object {  
    Class isa  OBJC_ISA_AVAILABILITY;
};

struct objc_class {  
    Class isa  OBJC_ISA_AVAILABILITY;
#if !__OBJC2__
    Class super_class;
    const char *name;
    long version;
    long info;
    long instance_size;
    struct objc_ivar_list *ivars;
    **struct objc_method_list **methodLists**;
    **struct objc_cache *cache**;
    struct objc_protocol_list *protocols;
#endif
};

struct objc_method_list {  
    struct objc_method_list *obsolete;
    int method_count;

#ifdef __LP64__
    int space;
#endif

    /* variable length structure */
    struct objc_method method_list[1];
};

struct objc_method {  
    SEL method_name;
    char *method_types;    /* a string representing argument/return types */
    IMP method_imp;
};
```
*objec_method_list*本质是一个有*objc_method*元素的可变长度的数组。一个objc_method结构体有函数名：SEL，有表示函数类型的字符串：char，以及函数的实现：IMP。
例如objc_msgSend(obj, foo);
1.首先，通过obj的isa指针找到它的class；
2.在class的method list找foo；
3.如果class中没有找到foo，继续往它的superclass中找；
4.一旦找到foo这个函数，就去执行它的实现IMP。
为了解决效率问题，需要objc_class的另一个成员*objc_cache*，在找到foo之后，把foo的method_name作为key，method_imp作为value存起来。当再次收到fo消息的时候，直接在缓存里找。
### 2.动态方法解析和转发
在上面的过程中，如果foo没有找到怎么办？通常程序会挂掉，在此之前，Objective-C的运行时还有三次机会：

- `动态解析`
- `备援接收者`
- `完整的消息转发`

#### 1).动态方法解析
首先，Objective-C运行时调用*+resolveInstanceMethod:*或着*+resolveClassMethod:*,如果你添加了函数并返回YES，那运行时系统就会重新启动一次消息发送的过程。

```
void fooMethod(id obj, SEL _cmd) {
		NSLog(@"foo");
}

+ (BOOL)resolveInstanceMethod:(SEL)aSEL {
		if(aSEL == @selector(foo:)) {
			 class_addMethod([self class], aSEL, (IMP)fooMethod, "v@:");
			 return YES;
	}
	
	return [super resolveInstanceMethod];
}
```
如果reslove方法返回NO，运行时就会移到下一步：消息转发，备援接收者。
上面的例子可以重新写成

```
IMP fooIMP = imp_implementationWithBlock(^(id _self) {
		NSLog(@"foo");
});

class_addMethod([self class], aSEL, fooIMP, @"v@:");
```
#### 2).备援接收者
如果目标对象实现了*-forwardingTargetForSelector:*，Runtime这时就会调用这个方法，尝试找到一个能响应该消息的对象，如果获取到，则直接转发给它。如果返回nil，继续第三步。

```
- (id)forwardingTargetForSelector:(SEL)aSelector {
		if(aSelector == @selector(foo:)) {
			return alternateObject;
		}
		
		return [super forwardingTargetForSelector:aSelector];
}
```
只要这个方法返回的不是 nil 和 self，整个消息发送的过程就会被重启，当然发送的对象会变成你返回的那个对象。否则，就会继续下一步 。完整的消息转发会创建一个 NSInvocation 对象。
#### 3).完整的消息转发
这一步是 Runtime 最后一次给你挽救的机会。首先它会发送 -methodSignatureForSelector: 消息获得函数的参数和返回值类型。如果 -methodSignatureForSelector: 返回 nil ，Runtime 则会发出 -doesNotRecognizeSelector: 消息，程序这时也就挂掉了。如果返回了一个函数签名，Runtime 就会创建一个 NSInvocation 对象并发送 -forwardInvocation: 消息给目标对象。
NSInvocation 实际上就是对一个消息的描述，包括selector 以及参数等信息。所以你可以在 -forwardInvocation: 里修改传进来的 NSInvocation 对象，然后发送 -invokeWithTarget: 消息给它，传进去一个新的目标：

```
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    NSMethodSignature *signature = [super methodSignatureForSelector:aSelector];
    if (!signature) {
        if ([SomeClass instancesRespondToSelector:aSelector]) {
            signature = [SomeClass.instance methodSignatureForSelector:aSelector];
        }
    }
    return signature;
}
```

```
- (void)forwardInvocation:(NSInvocation *)invocation {
    SEL sel = invocation.selector;

    if([SomeClass.instance respondsToSelector:sel]) {
        [invocation invokeWithTarget:alternateObject];
    } 
    else {
        [self doesNotRecognizeSelector:sel];
    }
}
```
### Objective-C 中给一个对象发送消息会经过以下几个步骤：
	1. 在对象类的 dispatch table 中尝试找到该消息。如果找到了，跳到相应的函数IMP去执行实现代码；
	2. 如果没有找到，Runtime 会发送 +resolveInstanceMethod: 或者 +resolveClassMethod: 尝试去 resolve 这个消息；
	3. 如果 resolve 方法返回 NO，Runtime 就发送 -forwardingTargetForSelector:允许你把这个消息转发给另一个对象；
	4. 如果没有新的目标对象返回， Runtime 就会发送 -methodSignatureForSelector:和 -forwardInvocation: 消息。你可以发送 -invokeWithTarget: 消息来手动转发消息或者发送 -doesNotRecognizeSelector: 抛出异常。
![](https://raw.githubusercontent.com/kuroky/EffectiveObjc/master/12.%E6%B6%88%E6%81%AF%E8%BD%AC%E5%8F%91%E6%9C%BA%E5%88%B6/421484-7dcfac31d3f976fa.png)

## 方法交换
有个需求，对App的用户进行行为追踪。记录用户点击的页面。
#### 1.最直接的方式就是在每个*viewDidAppear*里添加纪录事件的代码。

```
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Logging
    [Logging logWithEventName:@“my view did appear”];
}
```
这种方式破坏了代码的整洁，也会导致大工作量。
#### 2.使用继承或类别

```
@implementation CustomViewController ()
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Logging
    [Logging logWithEventName:@“my view did appear”];
}
```
缺点也很明显：
1.需要继承*UIViewController*，*UITableViewController*。。。
2.不能保证其余开发者在写新界面也会继承*CustomViewController*。
#### 3.Method Swizzling
swizzle一个方法其实就是在程序运行时在Dispatch Table里做点改动，让这个方法的名字(SEL)对应到另一个IMP。
首先定义一个类别，添加将要Swizzled的方法：

```
@implementation UIViewController (Swizzling)

- (void)pageStatic_viewWillAppear:(BOOL)animated {
    [self pageStatic_viewWillAppear:animated];
   
    NSString *pageName = [NSString stringWithFormat:@"%@",[self class]];
    [MobClick beginLogPageView:pageName];
}
```
调用*viewDidAppear:*会调用上面实现的*pageStatic_viewWillAppear:*，而在*pageStatic_viewWillAppear:*里调用*pageStatic_viewWillAppear:*实际上调用的是原来的*viewDidAppear:*。

接下来实现swizzle的方法：

```
+ (void)beginStaticPage {
		Class class = [self class];
		
		SEL originalSelector = @selector(viewWillAppear:);
		SEL swizzledSelector = @selector(pageStatic_viewWillAppear:);
		
		Method originalMethod = class_getInstanceMethod(class, originalSelector);
		Method swizzledMethod = class_getInstanceMethod(class, swizzledelector);
		
		BOOL didAddMethod = class_addMethod(class, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
		
		if(didAddMethod) {
			class_replaceMethod(class, swizzledSelector,method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod))
		}
		elese {
			method_exchangeImplementations(originalMethod, swizzledMethod);
		}
}
```
需要解释的是*class_addMethod*。要先尝试添加原selector是为了做一层保护，因为如果这个类没有实现*originalSelector*，但其父类实现了，那*class_getInstanceMethod*会返回父类的方法，这样*method_exchangeImplementations*替换的是父类的那个方法，所以我们先尝试添加*orginalSelector*，如果已经存在，在用*method_exchangeImplementations*把原方法的实现根新的方法给交换掉。

最后，我们只需要在程序启动的时候调用*beginStaticPage*

```
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
    
        [UIViewController beginStaticPage];
    });
}
```
一般情况下，类别里的方法会重写掉主类里相同名的方法。如果有两个类别实现了相同命名的方法，只有一个方法会被调用。但 +load: 是个特例，当一个类被读到内存的时候， runtime 会给这个类及它的每一个类别都发送一个 +load: 消息。
第三方库[Aspects](https://github.com/steipete/Aspects)封装了Runtime。

```
+ (id<AspectToken>)aspect_hookSelector:(SEL)selector
                          withOptions:(AspectOptions)options
                       usingBlock:(id)block
                            error:(NSError **)error;
- (id<AspectToken>)aspect_hookSelector:(SEL)selector
                      withOptions:(AspectOptions)options
                       usingBlock:(id)block
                            error:(NSError **)error;
```


