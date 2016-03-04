/*
 File: SquareCamViewController.m
 Abstract: Dmonstrates iOS 5 features of the AVCaptureStillImageOutput class
 Version: 1.0
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2013 Apple Inc. All Rights Reserved.
 
 */

#import "SquareCamViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AssertMacros.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#include <sys/time.h>

#import <DeepBelief/DeepBelief.h>

#pragma mark -

const NSInteger kPositivePredictionTotal = 100;
const NSInteger kNegativePredictionTotal = 100;

NS_ENUM(NSUInteger, EPredictionState) {
    eWaiting = 0,
    ePositiveLearning,
    eNegativeWaiting,
    eNegativeLearning,
    ePredicting,
};

static CGFloat DegreesToRadians(CGFloat degrees) { return degrees * M_PI / 180; };

// utility used by newSquareOverlayedImageForFeatures for
static CGContextRef CreateCGBitmapContextForSize(CGSize size);
static CGContextRef CreateCGBitmapContextForSize(CGSize size) {
    CGContextRef context = NULL;
    CGColorSpaceRef colorSpace;
    int bitmapBytesPerRow;
    
    bitmapBytesPerRow = (size.width * 4);
    
    colorSpace = CGColorSpaceCreateDeviceRGB();
    context = CGBitmapContextCreate(NULL, size.width, size.height,
                                    8, // bits per component
                                    bitmapBytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast);
    CGContextSetAllowsAntialiasing(context, NO);
    CGColorSpaceRelease(colorSpace);
    return context;
}

#pragma mark -

@interface UIImage (RotationMethods)
- (UIImage *)imageRotatedByDegrees:(CGFloat)degrees;
@end

@implementation UIImage (RotationMethods)

- (UIImage *)imageRotatedByDegrees:(CGFloat)degrees {
    // calculate the size of the rotated view's containing box for our drawing space
    UIView *rotatedViewBox = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.size.width, self.size.height)];
    CGAffineTransform t = CGAffineTransformMakeRotation(DegreesToRadians(degrees));
    rotatedViewBox.transform = t;
    CGSize rotatedSize = rotatedViewBox.frame.size;
    
    // Create the bitmap context
    UIGraphicsBeginImageContext(rotatedSize);
    CGContextRef bitmap = UIGraphicsGetCurrentContext();
    
    // Move the origin to the middle of the image so we will rotate and scale around the center.
    CGContextTranslateCTM(bitmap, rotatedSize.width / 2, rotatedSize.height / 2);
    
    //   // Rotate the image context
    CGContextRotateCTM(bitmap, DegreesToRadians(degrees));
    
    // Now, draw the rotated/scaled image into the context
    CGContextScaleCTM(bitmap, 1.0, -1.0);
    CGContextDrawImage(bitmap,
                       CGRectMake(-self.size.width / 2, -self.size.height / 2, self.size.width, self.size.height),
                       [self CGImage]);
    
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}

@end

#pragma mark -

@interface SquareCamViewController (InternalMethods)
- (void)setupAVCapture;
- (void)teardownAVCapture;
@end

@implementation SquareCamViewController

- (void)setupAVCapture {
    NSError *error = nil;
    
    session = [AVCaptureSession new];
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
        [session setSessionPreset:AVCaptureSessionPreset640x480];
    else
        [session setSessionPreset:AVCaptureSessionPresetPhoto];
    
    // Select a video device, make an input
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    
    if (error) {
        UIAlertView *alertView = [[UIAlertView alloc]
                                  initWithTitle:[NSString stringWithFormat:@"Failed with error %d", (int)[error code]]
                                  message:[error localizedDescription]
                                  delegate:nil
                                  cancelButtonTitle:@"Dismiss"
                                  otherButtonTitles:nil];
        [alertView show];
        [self teardownAVCapture];
        return;
    }
    
    if ([session canAddInput:deviceInput])
        [session addInput:deviceInput];
    
    // Make a video data output
    videoDataOutput = [AVCaptureVideoDataOutput new];
    
    // we want BGRA, both CoreGraphics and OpenGL work well with 'BGRA'
    NSDictionary *rgbOutputSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCMPixelFormat_32BGRA]
                                                                  forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    [videoDataOutput setVideoSettings:rgbOutputSettings];
    [videoDataOutput setAlwaysDiscardsLateVideoFrames:YES]; // discard if the data output queue is blocked (as we
    // process the still image)
    
    // create a serial dispatch queue used for the sample buffer delegate as well as when a still image is captured
    // a serial dispatch queue must be used to guarantee that video frames will be delivered in order
    // see the header doc for setSampleBufferDelegate:queue: for more information
    videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
    [videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];
    
    if ([session canAddOutput:videoDataOutput])
        [session addOutput:videoDataOutput];
    [[videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:YES];
    
    previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
    [previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
    [previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
    CALayer *rootLayer = [previewView layer];
    [rootLayer setMasksToBounds:YES];
    [previewLayer setFrame:[rootLayer bounds]];
    [rootLayer addSublayer:previewLayer];
    [session startRunning];
}

// clean up capture setup
- (void)teardownAVCapture {
    [previewLayer removeFromSuperlayer];
}

// utility routing used during image capture to set up capture orientation
- (AVCaptureVideoOrientation)avOrientationForDeviceOrientation:(UIDeviceOrientation)deviceOrientation {
    AVCaptureVideoOrientation result = AVCaptureVideoOrientationPortrait;
    if (deviceOrientation == UIDeviceOrientationPortraitUpsideDown) {
        result = AVCaptureVideoOrientationPortraitUpsideDown;
    } else if (deviceOrientation == UIDeviceOrientationLandscapeLeft) {
        result = AVCaptureVideoOrientationLandscapeLeft;
    } else if (deviceOrientation == UIDeviceOrientationLandscapeRight) {
        result = AVCaptureVideoOrientationLandscapeRight;
    }
    return result;
}

// utility routine to create a new image with the red square overlay with appropriate orientation
// and return the new composited image which can be saved to the camera roll
- (CGImageRef)newSquareOverlayedImageForFeatures:(NSArray *)features
                                       inCGImage:(CGImageRef)backgroundImage
                                 withOrientation:(UIDeviceOrientation)orientation
                                     frontFacing:(BOOL)isFrontFacing {
    CGImageRef returnImage = NULL;
    CGRect backgroundImageRect =
    CGRectMake(0., 0., CGImageGetWidth(backgroundImage), CGImageGetHeight(backgroundImage));
    CGContextRef bitmapContext = CreateCGBitmapContextForSize(backgroundImageRect.size);
    CGContextClearRect(bitmapContext, backgroundImageRect);
    CGContextDrawImage(bitmapContext, backgroundImageRect, backgroundImage);
    CGFloat rotationDegrees = 0.;
    
    switch (orientation) {
        case UIDeviceOrientationPortrait:
            rotationDegrees = -90.;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            rotationDegrees = 90.;
            break;
        case UIDeviceOrientationLandscapeLeft:
            if (isFrontFacing)
                rotationDegrees = 180.;
            else
                rotationDegrees = 0.;
            break;
        case UIDeviceOrientationLandscapeRight:
            if (isFrontFacing)
                rotationDegrees = 0.;
            else
                rotationDegrees = 180.;
            break;
        case UIDeviceOrientationFaceUp:
        case UIDeviceOrientationFaceDown:
        default:
            break; // leave the layer in its last known orientation
    }
    UIImage *rotatedSquareImage = [square imageRotatedByDegrees:rotationDegrees];
    
    // features found by the face detector
    for (CIFaceFeature *ff in features) {
        CGRect faceRect = [ff bounds];
        CGContextDrawImage(bitmapContext, faceRect, [rotatedSquareImage CGImage]);
    }
    returnImage = CGBitmapContextCreateImage(bitmapContext);
    CGContextRelease(bitmapContext);
    
    return returnImage;
}

// utility routine to display error aleart if takePicture fails
- (void)displayErrorOnMainQueue:(NSError *)error withMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        UIAlertView *alertView =
        [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"%@ (%d)", message, (int)[error code]]
                                   message:[error localizedDescription]
                                  delegate:nil
                         cancelButtonTitle:@"Dismiss"
                         otherButtonTitles:nil];
        [alertView show];
    });
}

// main action method to take a still image -- if face detection has been turned on and a face has been detected
// the square overlay will be composited on top of the captured image and saved to the camera roll
- (IBAction)takePicture:(id)sender {
    switch (predictionState) {
        case eWaiting: {
            [sender setTitle:@"Learning" forState:UIControlStateNormal];
            [self triggerNextState];
        } break;
            
        case ePositiveLearning: {
            // Do nothing
        } break;
            
        case eNegativeWaiting: {
            [sender setTitle:@"Learning" forState:UIControlStateNormal];
            [self triggerNextState];
        } break;
            
        case eNegativeLearning: {
            // Do nothing
        } break;
            
        case ePredicting: {
            [self triggerNextState];
        } break;
            
        default: {
            assert(FALSE); // Should never get here
        } break;
    }
}

// find where the video box is positioned within the preview layer based on the video size and gravity
+ (CGRect)videoPreviewBoxForGravity:(NSString *)gravity frameSize:(CGSize)frameSize apertureSize:(CGSize)apertureSize {
    CGFloat apertureRatio = apertureSize.height / apertureSize.width;
    CGFloat viewRatio = frameSize.width / frameSize.height;
    
    CGSize size = CGSizeZero;
    if ([gravity isEqualToString:AVLayerVideoGravityResizeAspectFill]) {
        if (viewRatio > apertureRatio) {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        } else {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResizeAspect]) {
        if (viewRatio > apertureRatio) {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        } else {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResize]) {
        size.width = frameSize.width;
        size.height = frameSize.height;
    }
    
    CGRect videoBox;
    videoBox.size = size;
    if (size.width < frameSize.width)
        videoBox.origin.x = (frameSize.width - size.width) / 2;
    else
        videoBox.origin.x = (size.width - frameSize.width) / 2;
    
    if (size.height < frameSize.height)
        videoBox.origin.y = (frameSize.height - size.height) / 2;
    else
        videoBox.origin.y = (size.height - frameSize.height) / 2;
    
    return videoBox;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    [self runCNNOnFrame:pixelBuffer];
}

- (void)runCNNOnFrame:(CVPixelBufferRef)pixelBuffer {
    assert(pixelBuffer != NULL);
    
    OSType sourcePixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    int doReverseChannels;
    if (kCVPixelFormatType_32ARGB == sourcePixelFormat) {
        doReverseChannels = 1;
    } else if (kCVPixelFormatType_32BGRA == sourcePixelFormat) {
        doReverseChannels = 0;
    } else {
        assert(false); // Unknown source format
    }
    
    const int sourceRowBytes = (int)CVPixelBufferGetBytesPerRow(pixelBuffer);
    const int width = (int)CVPixelBufferGetWidth(pixelBuffer);
    const int fullHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    unsigned char *sourceBaseAddr = CVPixelBufferGetBaseAddress(pixelBuffer);
    int height;
    unsigned char *sourceStartAddr;
    if (fullHeight <= width) {
        height = fullHeight;
        sourceStartAddr = sourceBaseAddr;
    } else {
        height = width;
        const int marginY = ((fullHeight - width) / 2);
        sourceStartAddr = (sourceBaseAddr + (marginY * sourceRowBytes));
    }
    void *cnnInput = jpcnn_create_image_buffer_from_uint8_data(sourceStartAddr, width, height, 4, sourceRowBytes,
                                                               doReverseChannels, 1);
    float *predictions;
    int predictionsLength;
    char **predictionsLabels;
    int predictionsLabelsLength;
    
    struct timeval start;
    gettimeofday(&start, NULL);
    jpcnn_classify_image(network, cnnInput, JPCNN_RANDOM_SAMPLE, -2, &predictions, &predictionsLength,
                         &predictionsLabels, &predictionsLabelsLength);
    //    struct timeval end;
    //    gettimeofday(&end, NULL);
    //    const long seconds = end.tv_sec - start.tv_sec;
    //    const long useconds = end.tv_usec - start.tv_usec;
    //    const float duration = ((seconds)*1000 + useconds / 1000.0) + 0.5;
    //  NSLog(@"Took %f ms", duration);
    
    jpcnn_destroy_image_buffer(cnnInput);
    
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [self handleNetworkPredictions:predictions withLength:predictionsLength];
    });
}

- (void)dealloc {
    [self teardownAVCapture];
}

#pragma mark - View lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSString *networkPath = [[NSBundle mainBundle] pathForResource:@"jetpac" ofType:@"ntwk"];
    if (networkPath == NULL) {
        fprintf(stderr, "Couldn't find the neural network parameters file - did you add it as a resource to your "
                "application?\n");
        assert(false);
    }
    network = jpcnn_create_network([networkPath UTF8String]);
    assert(network != NULL);
    
    [self setupLearning];
    
    [self setupAVCapture];
    square = [UIImage imageNamed:@"squarePNG"];
    
    labelLayers = [[NSMutableArray alloc] init];
    
    oldPredictionValues = [[NSMutableDictionary alloc] init];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)setPredictionValues:(NSDictionary *)newValues {
    const float decayValue = 0.75f;
    const float updateValue = 0.25f;
    const float minimumThreshold = 0.01f;
    
    NSMutableDictionary *decayedPredictionValues = [[NSMutableDictionary alloc] init];
    for (NSString *label in oldPredictionValues) {
        NSNumber *oldPredictionValueObject = [oldPredictionValues objectForKey:label];
        const float oldPredictionValue = [oldPredictionValueObject floatValue];
        const float decayedPredictionValue = (oldPredictionValue * decayValue);
        if (decayedPredictionValue > minimumThreshold) {
            NSNumber *decayedPredictionValueObject = [NSNumber numberWithFloat:decayedPredictionValue];
            [decayedPredictionValues setObject:decayedPredictionValueObject forKey:label];
        }
    }
    oldPredictionValues = decayedPredictionValues;
    
    for (NSString *label in newValues) {
        NSNumber *newPredictionValueObject = [newValues objectForKey:label];
        NSNumber *oldPredictionValueObject = [oldPredictionValues objectForKey:label];
        if (!oldPredictionValueObject) {
            oldPredictionValueObject = [NSNumber numberWithFloat:0.0f];
        }
        const float newPredictionValue = [newPredictionValueObject floatValue];
        const float oldPredictionValue = [oldPredictionValueObject floatValue];
        const float updatedPredictionValue = (oldPredictionValue + (newPredictionValue * updateValue));
        NSNumber *updatedPredictionValueObject = [NSNumber numberWithFloat:updatedPredictionValue];
        [oldPredictionValues setObject:updatedPredictionValueObject forKey:label];
    }
    NSArray *candidateLabels = [NSMutableArray array];
    for (NSString *label in oldPredictionValues) {
        NSNumber *oldPredictionValueObject = [oldPredictionValues objectForKey:label];
        const float oldPredictionValue = [oldPredictionValueObject floatValue];
        if (oldPredictionValue > 0.05f) {
            NSDictionary *entry = @{ @"label": label, @"value": oldPredictionValueObject };
            candidateLabels = [candidateLabels arrayByAddingObject:entry];
        }
    }
    NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"value" ascending:NO];
    NSArray *sortedLabels = [candidateLabels sortedArrayUsingDescriptors:[NSArray arrayWithObject:sort]];
    
    const float leftMargin = 10.0f;
    const float topMargin = 10.0f;
    
    const float valueWidth = 48.0f;
    const float valueHeight = 26.0f;
    
    const float labelWidth = 246.0f;
    const float labelHeight = 26.0f;
    
    const float labelMarginX = 5.0f;
    const float labelMarginY = 5.0f;
    
    [self removeAllLabelLayers];
    
    int labelCount = 0;
    for (NSDictionary *entry in sortedLabels) {
        NSString *label = [entry objectForKey:@"label"];
        NSNumber *valueObject = [entry objectForKey:@"value"];
        const float value = [valueObject floatValue];
        
        const float originY = (topMargin + ((labelHeight + labelMarginY) * labelCount));
        
        const int valuePercentage = (int)roundf(value * 100.0f);
        
        const float valueOriginX = leftMargin;
        NSString *valueText = [NSString stringWithFormat:@"%d%%", valuePercentage];
        
        [self addLabelLayerWithText:valueText
                            originX:valueOriginX
                            originY:originY
                              width:valueWidth
                             height:valueHeight
                          alignment:kCAAlignmentRight];
        
        const float labelOriginX = (leftMargin + valueWidth + labelMarginX);
        
        [self addLabelLayerWithText:[label capitalizedString]
                            originX:labelOriginX
                            originY:originY
                              width:labelWidth
                             height:labelHeight
                          alignment:kCAAlignmentLeft];
        
        labelCount += 1;
        if (labelCount > 4) {
            break;
        }
    }
}

- (void)removeAllLabelLayers {
    for (CATextLayer *layer in labelLayers) {
        [layer removeFromSuperlayer];
    }
    [labelLayers removeAllObjects];
}

- (void)addLabelLayerWithText:(NSString *)text
                      originX:(float)originX
                      originY:(float)originY
                        width:(float)width
                       height:(float)height
                    alignment:(NSString *)alignment {
    NSString *const font = @"Menlo-Regular";
    const float fontSize = 20.0f;
    
    const float marginSizeX = 5.0f;
    const float marginSizeY = 2.0f;
    
    const CGRect backgroundBounds = CGRectMake(originX, originY, width, height);
    
    const CGRect textBounds = CGRectMake((originX + marginSizeX), (originY + marginSizeY), (width - (marginSizeX * 2)),
                                         (height - (marginSizeY * 2)));
    
    CATextLayer *background = [CATextLayer layer];
    [background setBackgroundColor:[UIColor blackColor].CGColor];
    [background setOpacity:0.5f];
    [background setFrame:backgroundBounds];
    background.cornerRadius = 5.0f;
    
    [[self.view layer] addSublayer:background];
    [labelLayers addObject:background];
    
    CATextLayer *layer = [CATextLayer layer];
    [layer setForegroundColor:[UIColor whiteColor].CGColor];
    [layer setFrame:textBounds];
    [layer setAlignmentMode:alignment];
    [layer setWrapped:YES];
    [layer setFont:(__bridge CFTypeRef _Nullable)(font)];
    [layer setFontSize:fontSize];
    layer.contentsScale = [[UIScreen mainScreen] scale];
    [layer setString:text];
    
    [[self.view layer] addSublayer:layer];
    [labelLayers addObject:layer];
}

- (void)setPredictionText:(NSString *)text withDuration:(float)duration {
    if (duration > 0.0) {
        CABasicAnimation *colorAnimation = [CABasicAnimation animationWithKeyPath:@"foregroundColor"];
        colorAnimation.duration = duration;
        colorAnimation.fillMode = kCAFillModeForwards;
        colorAnimation.removedOnCompletion = NO;
        colorAnimation.fromValue = (id)[UIColor darkGrayColor].CGColor;
        colorAnimation.toValue = (id)[UIColor whiteColor].CGColor;
        colorAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        [self.predictionTextLayer addAnimation:colorAnimation forKey:@"colorAnimation"];
    } else {
        self.predictionTextLayer.foregroundColor = [UIColor whiteColor].CGColor;
    }
    
    [self.predictionTextLayer removeFromSuperlayer];
    [[self.view layer] addSublayer:self.predictionTextLayer];
    [self.predictionTextLayer setString:text];
}

- (void)setupLearning {
    negativePredictionsCount = 0;
    
    trainer = NULL;
    predictor = NULL;
    predictionState = eWaiting;
    
    lastInfo = NULL;
    
    [self setupInfoDisplay];
}

- (void)triggerNextState {
    switch (predictionState) {
        case eWaiting: {
            [self startPositiveLearning];
        } break;
            
        case ePositiveLearning: {
            [self startNegativeWaiting];
        } break;
            
        case eNegativeWaiting: {
            [self startNegativeLearning];
        } break;
            
        case eNegativeLearning: {
            [self startPredicting];
        } break;
            
        case ePredicting: {
            [self restartLearning];
        } break;
            
        default: {
            assert(FALSE); // Should never get here
        } break;
    }
}

- (void)startPositiveLearning {
    if (trainer != NULL) {
        jpcnn_destroy_trainer(trainer);
    }
    trainer = jpcnn_create_trainer();
    
    positivePredictionsCount = 0;
    predictionState = ePositiveLearning;
    
    [self updateInfoDisplay];
}

- (void)startNegativeWaiting {
    predictionState = eNegativeWaiting;
    [self updateInfoDisplay];
}

- (void)startNegativeLearning {
    negativePredictionsCount = 0;
    predictionState = eNegativeLearning;
    
    [self updateInfoDisplay];
}

- (NSString *)applicationDocumentsDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = paths.firstObject;
    return basePath;
}

- (void)startPredicting {
    if (predictor != NULL) {
        jpcnn_destroy_predictor(predictor);
    }
    predictor = jpcnn_create_predictor_from_trainer(trainer);
    NSString *fileName = [[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"txt"];
    NSString *filePath = [[self applicationDocumentsDirectory] stringByAppendingPathComponent:fileName];
    jpcnn_save_predictor([filePath UTF8String], predictor);
    //    NSString *thePredictor = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
    predictionState = ePredicting;
    
    [self updateInfoDisplay];
    
    self.lastFrameTime = [NSDate date];
}

- (void)restartLearning {
    [self startPositiveLearning];
}

- (void)setupInfoDisplay {
    NSString *const font = @"Menlo-Regular";
    const float fontSize = 20.0f;
    
    const float viewWidth = 320.0f;
    
    const float marginSizeX = 5.0f;
    const float marginSizeY = 5.0f;
    const float marginTopY = 7.0f;
    
    const float progressHeight = 20.0f;
    
    const float infoHeight = 150.0f;
    
    const CGRect progressBackgroundBounds =
    CGRectMake(marginSizeX, marginTopY, (viewWidth - (marginSizeX * 2)), progressHeight);
    
    self.progressBackground = [CATextLayer layer];
    [self.progressBackground setBackgroundColor:[UIColor blackColor].CGColor];
    [self.progressBackground setOpacity:0.5f];
    [self.progressBackground setFrame:progressBackgroundBounds];
    self.progressBackground.cornerRadius = 5.0f;
    
    [[self.view layer] addSublayer:self.progressBackground];
    
    const CGRect progressForegroundBounds = CGRectMake(marginSizeX, marginTopY, 0.0f, progressHeight);
    
    self.progressForeground = [CATextLayer layer];
    [self.progressForeground setBackgroundColor:[UIColor blueColor].CGColor];
    [self.progressForeground setOpacity:0.75f];
    [self.progressForeground setFrame:progressForegroundBounds];
    self.progressForeground.cornerRadius = 5.0f;
    
    [[self.view layer] addSublayer:self.progressForeground];
    
    const CGRect infoBackgroundBounds = CGRectMake(marginSizeX, (marginSizeY + progressHeight + marginSizeY),
                                                   (viewWidth - (marginSizeX * 2)), infoHeight);
    
    self.infoBackground = [CATextLayer layer];
    [self.infoBackground setBackgroundColor:[UIColor blackColor].CGColor];
    [self.infoBackground setOpacity:0.5f];
    [self.infoBackground setFrame:infoBackgroundBounds];
    self.infoBackground.cornerRadius = 5.0f;
    
    [[self.view layer] addSublayer:self.infoBackground];
    
    const CGRect infoForegroundBounds = CGRectInset(infoBackgroundBounds, 5.0f, 5.0f);
    
    self.infoForeground = [CATextLayer layer];
    [self.infoForeground setBackgroundColor:[UIColor clearColor].CGColor];
    [self.infoForeground setForegroundColor:[UIColor whiteColor].CGColor];
    [self.infoForeground setOpacity:1.0f];
    [self.infoForeground setFrame:infoForegroundBounds];
    [self.infoForeground setWrapped:YES];
    [self.infoForeground setFont:(__bridge CFTypeRef _Nullable)(font)];
    [self.infoForeground setFontSize:fontSize];
    self.infoForeground.contentsScale = [[UIScreen mainScreen] scale];
    
    [self.infoForeground setString:@""];
    
    [[self.view layer] addSublayer:self.infoForeground];
}

- (void)updateInfoDisplay {
    
    switch (predictionState) {
        case eWaiting: {
            [self setInfo:@"When you're ready to teach me, press the button at the bottom and point your phone at the "
             @"thing you want to recognize."];
            [self setProgress:0.0f];
        } break;
            
        case ePositiveLearning: {
            [self setInfo:@"Move around the thing you want to recognize, keeping the phone pointed at it, to capture "
             @"different angles."];
            [self setProgress:(positivePredictionsCount / (float)kPositivePredictionTotal)];
        } break;
            
        case eNegativeWaiting: {
            [self setInfo:@"Now I need to see examples of things that aren't the object you're looking for. Press the "
             @"button when you're ready."];
            [self setProgress:0.0f];
            [self.mainButton setTitle:@"Continue Learning" forState:UIControlStateNormal];
        } break;
            
        case eNegativeLearning: {
            [self setInfo:@"Now move around the room pointing your phone at lots of things that are not the object you "
             @"want to recognize."];
            [self setProgress:(negativePredictionsCount / (float)kNegativePredictionTotal)];
        } break;
            
        case ePredicting: {
            [self setInfo:@"You've taught the neural network to see! Now you should be able to scan around using the "
             @"camera and detect the object's presence."];
            [self.mainButton setTitle:@"Learn Again" forState:UIControlStateNormal];
        } break;
            
        default: {
            assert(FALSE); // Should never get here
        } break;
    }
}

- (void)setInfo:(NSString *)info {
    if (![info isEqualToString:lastInfo]) {
        [self.infoForeground setString:info];
        lastInfo = info;
    }
}

- (void)setProgress:(float)amount {
    const CGRect progressBackgroundBounds = [self.progressBackground frame];
    
    const float fullWidth = progressBackgroundBounds.size.width;
    const float foregroundWidth = (fullWidth * amount);
    
    CGRect progressForegroundBounds = [self.progressForeground frame];
    progressForegroundBounds.size.width = foregroundWidth;
    [self.progressForeground setFrame:progressForegroundBounds];
}

- (void)handleNetworkPredictions:(float *)predictions withLength:(int)predictionsLength {
    switch (predictionState) {
        case eWaiting: {
            // Do nothing
        } break;
            
        case ePositiveLearning: {
            jpcnn_train(trainer, 1.0f, predictions, predictionsLength);
            positivePredictionsCount += 1;
            if (positivePredictionsCount >= kPositivePredictionTotal) {
                [self triggerNextState];
            }
        } break;
            
        case eNegativeWaiting: {
            // Do nothing
        } break;
            
        case eNegativeLearning: {
            jpcnn_train(trainer, 0.0f, predictions, predictionsLength);
            negativePredictionsCount += 1;
            if (negativePredictionsCount >= kNegativePredictionTotal) {
                [self triggerNextState];
            }
        } break;
            
        case ePredicting: {
            const float predictionValue = jpcnn_predict(predictor, predictions, predictionsLength);
            [self setProgress:predictionValue];
            self.lastFrameTime = [NSDate date];
        } break;
            
        default: {
            assert(FALSE); // Should never get here
        } break;
    }
    
    [self updateInfoDisplay];
}

@end
