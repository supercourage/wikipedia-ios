//  Created by Monte Hurd on 10/24/14.
//  Copyright (c) 2013 Wikimedia Foundation. Provided under MIT-style license; please copy and modify!

#import "WKWebView+LoadAssetsHtml.h"
#import "Wikipedia-Swift.h"
#import "WMFProxyServer.h"

@implementation WKWebView (LoadAssetsHtml)

- (void)loadHTMLFromAssetsFile:(NSString*)fileName scrolledToFragment:(NSString*)fragment {
    if (!fileName) {
        DDLogError(@"attempted to load nil file");
        return;
    }
    
    fragment = fragment ? fragment : @"top";
    NSURL* requestURL = [[WMFProxyServer sharedProxyServer] proxyURLForRelativeFilePath:fileName fragment:fragment];
    NSURLRequest* request = [NSURLRequest requestWithURL:requestURL];
    [self loadRequest:request];
}

- (void)loadHTML:(NSString*)string withAssetsFile:(NSString*)fileName scrolledToFragment:(NSString*)fragment topPadding:(NSUInteger)topPadding {
    if (!string) {
        string = @"";
    }
    
    WMFProxyServer *proxyServer = [WMFProxyServer sharedProxyServer];
    
    
    NSUInteger windowPixelWidth = (NSUInteger)(MIN(self.bounds.size.width, self.bounds.size.height) * self.window.screen.scale);
    
    NSUInteger targetImageWidth = 320;
    
    if (windowPixelWidth < 640) {
        targetImageWidth = 320;
    } else if (windowPixelWidth < 800) {
        targetImageWidth = 640;
    } else if (windowPixelWidth < 1024) {
        targetImageWidth = 800;
    } else if (windowPixelWidth < 1280) {
        targetImageWidth = 1024;
    } else if (windowPixelWidth < 1920) {
        targetImageWidth = 1280;
    } else if (windowPixelWidth < 2560) {
        targetImageWidth = 1920;
    } else if (windowPixelWidth < 2880) {
        targetImageWidth = 2560;
    } else {
        targetImageWidth = 2880;
    }

    string = [proxyServer stringByReplacingImageURLsWithProxyURLsInHTMLString:string targetImageWidth:targetImageWidth];

    NSString* path = [[self getAssetsPath] stringByAppendingPathComponent:fileName];

    NSString* fileContents = [NSMutableString stringWithContentsOfFile:path
                                                              encoding:NSUTF8StringEncoding
                                                                 error:nil];

    NSNumber* fontSize   = [[NSUserDefaults standardUserDefaults] wmf_readingFontSize];
    NSString* fontString = [NSString stringWithFormat:@"%ld%%", fontSize.integerValue];

    NSAssert([fileContents componentsSeparatedByString:@"%@"].count == (3 + 1), @"\nHTML template file does not have required number of percent-ampersand occurences (3).\nNumber of percent-ampersands must match number of values passed to  'stringWithFormat:'");

    // index.html and preview.html have three "%@" subsitition markers. Replace both of these with actual content.
    NSString* templateAndContent = [NSString stringWithFormat:fileContents, fontString, @(topPadding), string];

    // Get temp file name. For a fileName of "index.html" the temp file name would be "index.temp.html"
    NSString* tempFileName = [[[fileName stringByDeletingPathExtension] stringByAppendingPathExtension:@"temp"] stringByAppendingPathExtension:[fileName pathExtension]];

    // Get path to tempFileName
    NSString* tempFilePath = [proxyServer localFilePathForRelativeFilePath:tempFileName];

    NSError* error = nil;
    [templateAndContent writeToFile:tempFilePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (!error) {
        [self loadHTMLFromAssetsFile:tempFileName scrolledToFragment:fragment];
    } else {
        NSAssert(NO, @"\nTemp file could not be written: \n%@\n", tempFilePath);
    }
}



- (NSString*)getAssetsPath {
    NSArray* documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [[documentsPath firstObject] stringByAppendingPathComponent:@"assets"];
}

@end