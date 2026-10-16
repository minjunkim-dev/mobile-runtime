#import <Foundation/Foundation.h>
int main(int argc, const char **argv) {
  @autoreleasepool {
    NSLog(@"Foundation temp=%@ ENV TMPDIR=%s", NSTemporaryDirectory(), getenv("TMPDIR"));
    NSURL *url = [NSURL fileURLWithPath:@(argv[1])];
    NSError *error = nil;
    BOOL ok = [[@"owned probe" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:url options:NSDataWritingAtomic error:&error];
    NSLog(@"atomic=%d error=%@", ok, error);
    error = nil;
    NSURL *replacement = [[NSFileManager defaultManager] URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask appropriateForURL:url create:NO error:&error];
    NSLog(@"replacement=%@ error=%@", replacement, error);
    return ok ? 0 : 1;
  }
}
