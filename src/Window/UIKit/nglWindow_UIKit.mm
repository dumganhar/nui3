#include "nui.h"

#include "nglApplication.h"
#include "nglVideoMode.h"
#include "nglContext.h"
#include "nglWindow.h"
#include "nglKeyboard.h"
#include "nuiMouseCursor.h"
#include "nuiStopWatch.h"

#include <QuartzCore/QuartzCore.h>


#include <string.h>

#include "nglWindow_UIKit.h"

#include <GL/gl.h>

#define NGL_WINDOW_FPS 60.0f

//#include "nglImage.h"

#define NGL_WINDOW_EBASE      (NGL_CONTEXT_ELAST+1)
#define NGL_WINDOW_ESYSWIN    (NGL_WINDOW_EBASE+1)
#define NGL_WINDOW_EVIDMODE   (NGL_WINDOW_EBASE+2)
#define NGL_WINDOW_ERANGE     (NGL_WINDOW_EBASE+3)

const nglChar* gpWindowErrorTable[] =
{
  /*  0 */ _T("No error"),
  /*  1 */ _T("System window creation failed"),
  /*  2 */ _T("Full screen video mode unavailable"),
  /*  3 */ _T("Properties out of range"),
  NULL
};

#ifndef _DEBUG_
#undef NGL_OUT
#define NGL_OUT {}
#endif

#if defined(_MULTI_TOUCHES_) && 0//defined(_DEBUG_)
# define NGL_TOUCHES_OUT NGL_OUT
#else//!_MULTI_TOUCHES_
# define NGL_TOUCHES_OUT {}
#endif//!_MULTI_TOUCHES_

//#define _DEBUG_WINDOW_

static std::list<nglTouchId> gAvailableTouches;
static nglTouchId gPressedTouches[_NUI_MAX_TOUCHES_];

void AdjustFromAngle(uint Angle, const nuiRect& rRect, nglMouseInfo& rInfo)
{
  switch (Angle)
  {
    case 90:
      {
        int tmpX= rInfo.X;
        rInfo.X = ((int)rRect.GetWidth()) - rInfo.Y;
        rInfo.Y = tmpX;
      }
      break;
    case 270:
      {
        int tmpY = rInfo.Y;
        rInfo.Y = ((int)rRect.GetHeight()) - rInfo.X;
        rInfo.X = tmpY;
      }
      break;
    case 180:
      {
        rInfo.X = ((int)rRect.GetWidth()) - rInfo.X;
        rInfo.Y = ((int)rRect.GetHeight()) - rInfo.Y;
      }
      break;
    case 0:
      {
      }
      break;
    default:
      {
        NGL_ASSERT(!"Unsupported rendering angle");
      }
  }
  NGL_TOUCHES_OUT(_T("AdjustFromAngle %d, X:%d Y:%d\n"), Angle, rInfo.X, rInfo.Y);
}

@implementation nglUIWindow

- (nglWindow *) getNGLWindow
{
	return self->mpNGLWindow;
}

+ (Class) layerClass
{
	return [CAEAGLLayer class];
}


- (id) initWithFrame: (CGRect) rect andNGLWindow: (nglWindow*) pNGLWindow
{
  glView = nil;
  glViewOld = nil;
  OrientationTimer = nil;
  UIDevice* pUIDev = [UIDevice currentDevice];
  oldorientation = pUIDev.orientation;
  mAngle = -1;
  
  if ( (self = [super initWithFrame: rect]) )
  {
    mpNGLWindow = pNGLWindow;
  }
  else
  {
    NGL_ASSERT(!"initWithFrame: Could not initialize UIWindow");
  }
  glView = [[EAGLView alloc] initWithFrame:rect replacing: nil];
  [self addSubview:glView];
  
  OrientationTimer = [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)((1.0 / 10.0)) target:self selector:@selector(UpdateOrientation) userInfo:nil repeats:TRUE];
  [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];

  [[UITextField alloc] initWithFrame: CGRectZero];

//NGL_OUT(_T("[nglUIWindow initWithFrame]\n"));
  mInited = false;
  mInvalidated = true;

  mInvalidationTimer = nil;
  mDisplayLink = nil;

  int frameInterval = 1;
  NSString* sysVersion = [[UIDevice currentDevice] systemVersion];
  if ([sysVersion compare:@"3.1" options:NSNumericSearch] != NSOrderedAscending) ///< CADisplayLink requires version 3.1 or greater
  {
    mDisplayLink = [NSClassFromString(@"CADisplayLink") displayLinkWithTarget:self selector:@selector(Paint)];
    [mDisplayLink setFrameInterval:frameInterval];
    [mDisplayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
  }
  else ///< NSTimer is used as fallback
  {
    mInvalidationTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0f / NGL_WINDOW_FPS) target:self selector:@selector(Paint) userInfo:nil repeats:YES];
  }
  
  mpTimer = nuiAnimation::AcquireTimer();
  mpTimer->Stop();

	[self initializeKeyboard];
  
  return self;
}

- (void) dealloc
{
  [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
  //NGL_OUT(_T("[nglUIWindow dealloc]\n"));
  mpNGLWindow->CallOnDestruction();

  nuiAnimation::ReleaseTimer();
  if (mInvalidationTimer != nil)
  {
    [mInvalidationTimer invalidate];
    //    [mInvalidationTimer release]; ///< should be auto released
    mInvalidationTimer = nil;
  }
  if (mDisplayLink != nil)
  {
    [mDisplayLink invalidate];
    //    [mDisplayLink release]; ///< should be auto released
    mDisplayLink = nil;
  }
  
  [OrientationTimer dealloc];
  [super dealloc];
}

- (void) UpdateKeyboard
{
  if (!mKeyboardVisible)
    return;

  [self hideKeyboard];
  [self showKeyboard];
}

- (void) UpdateOrientation
{
	
  //nuiStopWatch watch(_T("nglWindowUIKIT::UpdateOrientation"));
  int32 angle = -1;
  int32 w, h;
  w = mpNGLWindow->GetWidth();
  h = mpNGLWindow->GetHeight();
  
  bool forceresize = FALSE;
  UIApplication* pApp = [UIApplication sharedApplication];
  UIDevice* pUIDev = [UIDevice currentDevice];
  UIDeviceOrientation orientation = pUIDev.orientation;
  UIInterfaceOrientation apporientation = pApp.statusBarOrientation;

  if (mpNGLWindow->GetAutoRotation())
  {
    if (apporientation != orientation)
    {
      switch (orientation)
      {
        case UIDeviceOrientationUnknown:
        case UIDeviceOrientationFaceUp:
        case UIDeviceOrientationFaceDown:
          break;
        case UIDeviceOrientationPortrait:
          angle = 0;
          pApp.statusBarOrientation = UIInterfaceOrientationPortrait;
          [self UpdateKeyboard];
          w = [UIScreen mainScreen].applicationFrame.size.width;
          h = [UIScreen mainScreen].applicationFrame.size.height;
          break;
        case UIDeviceOrientationPortraitUpsideDown:
          angle = 180;
          pApp.statusBarOrientation = UIInterfaceOrientationPortraitUpsideDown;
          [self UpdateKeyboard];
          w = [UIScreen mainScreen].applicationFrame.size.width;
          h = [UIScreen mainScreen].applicationFrame.size.height;
          break;
        case UIDeviceOrientationLandscapeLeft:
          angle = 270;
          pApp.statusBarOrientation = UIInterfaceOrientationLandscapeRight;
          [self UpdateKeyboard];
          h = [UIScreen mainScreen].applicationFrame.size.width;
          w = [UIScreen mainScreen].applicationFrame.size.height;
          break;
        case UIDeviceOrientationLandscapeRight:
          angle = 90;
          pApp.statusBarOrientation = UIInterfaceOrientationLandscapeLeft;
          [self UpdateKeyboard];
          h = [UIScreen mainScreen].applicationFrame.size.width;
          w = [UIScreen mainScreen].applicationFrame.size.height;
          break;
      }
    }
    
    if (angle >= 0 && angle != mpNGLWindow->GetRotation())
    {
      if (mpNGLWindow->OnRotation(angle))
      {
        mpNGLWindow->SetRotation(angle);
        forceresize = YES;
        CGRect r = [self frame];
        printf("currentFrame: %f, %f - %f, %f\n", r.origin.x, r.origin.y, r.size.width, r.size.height);
        r = [UIScreen mainScreen].applicationFrame;
        printf("applicationFrame: %f, %f - %f, %f\n", r.origin.x, r.origin.y, r.size.width, r.size.height);
		  
        mInvalidated = true;
      }
    }

    if (mpNGLWindow->GetWidth() != w || mpNGLWindow->GetHeight() != h || oldorientation == orientation)
    {
      forceresize = YES;
    }
  }
  else
  {
    angle = mpNGLWindow->GetRotation();
    if (mAngle != angle)
    {
      printf("new window angle: %f (old %f)\n", angle, mAngle);
      switch (angle)
      {
        case 0:
          //UIDeviceOrientationPortrait
          if (pApp.statusBarOrientation != UIInterfaceOrientationPortrait)
          {
            pApp.statusBarOrientation = UIInterfaceOrientationPortrait;
            [self UpdateKeyboard];
          }
          w = [UIScreen mainScreen].applicationFrame.size.width;
          h = [UIScreen mainScreen].applicationFrame.size.height;
          break;
        case 90:
          //UIDeviceOrientationLandscapeRight
          if (pApp.statusBarOrientation != UIInterfaceOrientationLandscapeLeft)
          {
            pApp.statusBarOrientation = UIInterfaceOrientationLandscapeLeft;
            [self UpdateKeyboard];
          }
          h = [UIScreen mainScreen].applicationFrame.size.width;
          w = [UIScreen mainScreen].applicationFrame.size.height;
          break;
        case 180:
          //UIDeviceOrientationPortraitUpsideDown
          if (pApp.statusBarOrientation != UIInterfaceOrientationPortraitUpsideDown)
          {
            pApp.statusBarOrientation = UIInterfaceOrientationPortraitUpsideDown;
            [self UpdateKeyboard];
          }
          w = [UIScreen mainScreen].applicationFrame.size.width;
          h = [UIScreen mainScreen].applicationFrame.size.height;
          break;
        case 270:
          //UIDeviceOrientationLandscapeLeft
          if (pApp.statusBarOrientation != UIInterfaceOrientationLandscapeRight)
          {
            pApp.statusBarOrientation = UIInterfaceOrientationLandscapeRight;
            [self UpdateKeyboard];
          }
          h = [UIScreen mainScreen].applicationFrame.size.width;
          w = [UIScreen mainScreen].applicationFrame.size.height;
          break;
      }
      
      forceresize = YES;
    }
    
  }
  
  if (forceresize)
  {
    CGRect rect = [[UIScreen mainScreen] applicationFrame];
//    rect.size.width = w;
//    rect.size.height = h;
    printf("new window size: %f, %f\n", w, h);

    glViewOld = glView;
    self.frame = rect;
    
    glView = [[EAGLView alloc] initWithFrame:rect replacing: glViewOld];
    [self addSubview:glView];
    //[glView startAnimation];
    
    mpNGLWindow->SetSize(w, h);
  }   
  oldorientation = orientation;
  mAngle = angle;
}

- (void) InitNGLWindow
{  
  if (!mInited)
  {
    mInited = true;
    mpNGLWindow->CallOnCreation();
//    mpNGLWindow->Invalidate();
//    mpNGLWindow->CallOnPaint();
  }

  static int32 counter = 0;
  if (counter)
  {
    counter--;
    return;
  }
  
  counter = 60;

  [self UpdateOrientation];
}

- (void) sendEvent: (UIEvent*) pEvent
{
  double t = nglTime();
  [self InitNGLWindow];
  
//  NGL_OUT(_T("[nglUIWindow sendEvent]\n"));
//  [self dumpTouches: pEvent];
//nuiStopWatch watch(_T("nglWindowUIKIT::sendEvent"));
  nglWindow::EventMask mask = mpNGLWindow->GetEventMask();
  if (mask & nglWindow::MouseEvents)
  {
    [self handleEvent: pEvent];
  }

  mLastEventTime = t;
  [super sendEvent: pEvent];
}

/*
- (void) touchesChangedWithEvent: (UIEvent*) pEvent
{
//NGL_OUT(_T("[nglUIWindow touchesChangedWithEvent]\n"));
  [super touchesChangedWithEvent: pEvent];
}
*/

- (void) dumpTouch: (UITouch*) pTouch
{
  UITouchPhase touchPhase = [pTouch phase];
  uint touchTapCount = [pTouch tapCount];

  CGPoint newp = [pTouch locationInView: (UIView*)self];
  CGPoint oldp = [pTouch previousLocationInView: (UIView*)self];    

  NGL_OUT(_T("Touch Info [%p] [@%d]: [%s], [%d], [x:%f y:%f]->[x:%f y:%f]\n"),
            pTouch, [pTouch timestamp],
            touchPhase == UITouchPhaseBegan ?       "Clicked"   :
            touchPhase == UITouchPhaseMoved ?       "Moved"     :
            touchPhase == UITouchPhaseStationary ?  "Static"    :
            touchPhase == UITouchPhaseEnded ?       "Unclicked" :
            touchPhase == UITouchPhaseCancelled ?   "Canceled"  : "Unknown",
            touchTapCount,
            oldp.x, oldp.y,
            newp.x, newp.y
          );
}

- (void) dumpTouches: (UIEvent*) pEvent
{
  NSSet* pSet = [pEvent allTouches];
  NGL_ASSERT(pSet);
  NSArray* pArray = [pSet allObjects];
  NGL_ASSERT(pArray);
  NSUInteger count = [pArray count];
  NGL_OUT(_T("Dump touches info: %d\n"), count);

  std::vector<UITouch*> touches;
  touches.resize((uint)count);
  [pArray getObjects: &touches[0]];
  
  std::vector<UITouch*>::const_iterator end = touches.end();
  for (std::vector<UITouch*>::const_iterator it = touches.begin(); it != end; ++it)
  {
    UITouch* pTouch = *it;
    [self dumpTouch: pTouch];
  }
}

- (void)Paint
{
  [self InitNGLWindow];

  if (glViewOld)
  {
    [glViewOld removeFromSuperview];
    [glViewOld dealloc];
    glViewOld = nil;
  }
  //if (mInvalidated)
  {
    mInvalidated = false;
    //mpNGLWindow->CallOnPaint();
    mpTimer->Tick();
  }
}


- (void) handleEvent: (UIEvent*) pEvent
{
  //nuiStopWatch watch(_T("nglWindowUIKIT::handleEvent"));
	static double sOldTimestamp = 0.0;
  NSSet* pSet = [pEvent allTouches];
  NGL_ASSERT(pSet);
  NSArray* pArray = [pSet allObjects];
  NGL_ASSERT(pArray);
  NSUInteger count = [pArray count];

  std::vector<UITouch*> touches;
  touches.resize((uint)count);
  [pArray getObjects: &touches[0]];

  const nuiRect rect(0,0, mpNGLWindow->GetWidth(), mpNGLWindow->GetHeight());

  for (uint n = 0; n < count; n++)
  {
    UITouch* pTouch = touches[n];

//    UITouchInfo touchInfo = [pTouch info];
    UITouchPhase touchPhase = [pTouch phase];
    uint touchTapCount = [pTouch tapCount];

    CGPoint newp = [pTouch locationInView: (UIView*)self];
    CGPoint oldp = [pTouch previousLocationInView: (UIView*)self];

    int x = (int)newp.x;
    int y = (int)newp.y;
    
    TouchesInfo::iterator it = mTouches.find(pTouch);

    if (it != mTouches.end())
    {
///< this touch exists
      nglTouchInfo& rTouch(it->second);
      NGL_ASSERT(touchPhase != UITouchPhaseBegan);
      if (touchPhase == UITouchPhaseEnded || touchPhase == UITouchPhaseCancelled)
      {
///< this touch has been released
        NGL_TOUCHES_OUT(_T("[%p][%d] [available: %d] Release X:%d Y:%d, phase: %s\n"), pTouch, rTouch.mTouchId, gAvailableTouches.size(), x, y, touchPhase == UITouchPhaseEnded ? "UITouchPhaseEnded" : touchPhase == UITouchPhaseCancelled ? "UITouchPhaseEnded" : "SHALL NOT");
        
        nglMouseInfo info;
        info.Buttons = nglMouseInfo::ButtonLeft;
        info.X = x;
        info.Y = y;

        AdjustFromAngle(mpNGLWindow->GetRotation(), rect, info);

        info.SwipeInfo = nglMouseInfo::eNoSwipe;
        info.TouchId = rTouch.mTouchId;

///< if tapcount > 1, unclicked from a double click
//        if (touchTapCount > 1)// && ([pTouch timestamp] - sOldTimestamp < DOUBLE_TAP_DELAY))
//          info.Buttons |= nglMouseInfo::ButtonDoubleClick;

        mpNGLWindow->CallOnMouseUnclick(info);

        gAvailableTouches.push_back(rTouch.mTouchId);
        gPressedTouches[rTouch.mTouchId] = false;
        
        mTouches.erase(it);
        
      }
      else if (rTouch.X != x || rTouch.Y != y)
      {
///< this touch has moved
        NGL_TOUCHES_OUT(_T("[%p][%d] Move X:%d Y:%d\n"), pTouch, rTouch.mTouchId, x, y);
        NGL_ASSERT(touchPhase == UITouchPhaseMoved);
        rTouch.X = x;
        rTouch.Y = y;

        nglMouseInfo info;
        info.Buttons = nglMouseInfo::ButtonLeft;
        info.X = x;
        info.Y = y;

        AdjustFromAngle(mpNGLWindow->GetRotation(), rect, info);

        info.SwipeInfo = nglMouseInfo::eNoSwipe;
        info.TouchId = rTouch.mTouchId;
///< if tapcount > 1, moved from a double click
//        if (touchTapCount > 1)// && ([pTouch timestamp] - sOldTimestamp < DOUBLE_TAP_DELAY))
//          info.Buttons |= nglMouseInfo::ButtonDoubleClick;
        
        mpNGLWindow->CallOnMouseMove(info);
      }
      else
      {
        NGL_ASSERT(touchPhase == UITouchPhaseStationary);
      }
    }
    else if (touchPhase == UITouchPhaseBegan && (gAvailableTouches.size() > 0))
    {
///< this is a new touch
      NGL_TOUCHES_OUT(_T("[%p][available: %d] UITouchPhaseBegan X:%d Y:%d\n"), pTouch, gAvailableTouches.size(), x, y);

      NGL_ASSERT(touchPhase == UITouchPhaseBegan);

      nglTouchInfo newTouch;
      newTouch.X = x;
      newTouch.Y = y;
      NGL_ASSERT(gAvailableTouches.size() > 0);
      newTouch.mTouchId = gAvailableTouches.front();

      gAvailableTouches.pop_front();
      gPressedTouches[newTouch.mTouchId] = true;

      NGL_TOUCHES_OUT(_T("[%p][%d] New X:%d Y:%d\n"), pTouch, newTouch.mTouchId, x, y);
      mTouches[pTouch] = newTouch;

      nglMouseInfo info;
      info.Buttons = nglMouseInfo::ButtonLeft;

			// Double tapping events are way too slow on the iPhone
			// compare timestamps to see if we should declare the event a double click
#define DOUBLE_TAP_DELAY	0.25

///< if tapcount > 1, it is a double click
      if (touchTapCount > 1)// && ([pTouch timestamp] - sOldTimestamp < DOUBLE_TAP_DELAY))
        info.Buttons |= nglMouseInfo::ButtonDoubleClick;

			sOldTimestamp = [pTouch timestamp];

      info.X = x;
      info.Y = y;

      AdjustFromAngle(mpNGLWindow->GetRotation(), rect, info);

      info.SwipeInfo = nglMouseInfo::eNoSwipe;
      info.TouchId = newTouch.mTouchId;

      mpNGLWindow->CallOnMouseClick(info);
    }
    else
    {
      NGL_TOUCHES_OUT(_T("[%p][available: %d] Discarding event: [UITouchPhaseBegan X:%d Y:%d]\n"), pTouch, gAvailableTouches.size(), x, y);
    }
  }

/*
** Debug prints:
*/
/*
  NGL_OUT(_T("Available Touches count: %d\nIds: "), gAvailableTouches.size());
  for (std::list<nglTouchId>::const_iterator it = gAvailableTouches.begin(); it != gAvailableTouches.end(); ++it) {
    NGL_OUT(_T("[%d]"), *it);
  }
  NGL_OUT(_T("\n"));
*/
  //[self Paint];
}

- (void) invalidate
{
  mInvalidated = true;
}

/////// Keyboard support:
- (void)initializeKeyboard
{
	mpTextField = NULL;

	// Apparently CGRectZero breaks backspace in OS3.2 .. weird.
	mpTextField = [[UITextField alloc] initWithFrame: CGRectMake(0,0,160,50)];
	
	mpTextField.delegate = self;
	/* placeholder so there is something to delete! */
	mpTextField.text = @"x";	
	
	/* set UITextInputTrait properties, mostly to defaults */
	mpTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	mpTextField.autocorrectionType = UITextAutocorrectionTypeNo;
	mpTextField.enablesReturnKeyAutomatically = NO;
	mpTextField.keyboardAppearance = UIKeyboardAppearanceAlert;
	mpTextField.keyboardType = UIKeyboardTypeDefault;
	mpTextField.clearsOnBeginEditing = NO;
	mpTextField.returnKeyType = UIReturnKeyDefault;
	mpTextField.secureTextEntry = NO;	
	
	mpTextField.hidden = YES;
	mKeyboardVisible = NO;
	/* add the UITextField (hidden) to our view */
	[self addSubview: mpTextField];
	
}

// Show Keyboard
- (void)showKeyboard
{
	mKeyboardVisible = YES;
	[mpTextField becomeFirstResponder];
}

// hide onscreen virtual keyboard
- (void)hideKeyboard
{
	mKeyboardVisible = NO;
	[mpTextField resignFirstResponder];
}

// UITextFieldDelegate method.  Invoked when user types something.
- (BOOL)textField:(UITextField *)_textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
  NGL_OUT(_T("change chars in range %d - %d\n"), range.location, range.length);
	if ([string length] == 0)
  {
    mpNGLWindow->CallOnKeyDown(nglKeyEvent(NK_BACKSPACE, 8, 8)); // 8 = BS = BackSpace
    mpNGLWindow->CallOnKeyUp(nglKeyEvent(NK_BACKSPACE, 8, 8));
	}
	else
  {
    nglString str((CFStringRef)string);
    mpNGLWindow->CallOnTextInput(str);
	}

	return NO; /* don't allow the edit! (keep placeholder text there) */
}

/* Terminates the editing session */
- (BOOL)textFieldShouldReturn:(UITextField*)_textField
{
  bool res = false;
  
  res |= mpNGLWindow->CallOnKeyDown(nglKeyEvent(NK_ENTER, '\n', '\n'));
  res |= mpNGLWindow->CallOnKeyUp(nglKeyEvent(NK_ENTER, '\n', '\n'));

  if (!res)
  {
    if (!mpNGLWindow->CallOnTextInput(_T("\n")))
    {
      [self hideKeyboard];
      mpNGLWindow->CallOnTextInputCancelled();
      return YES;
    }
  }
	return NO;
}

- (BOOL)textFieldShouldClear:(UITextField*)_textField
{
	return NO;
}

- (void) MakeCurrent
{
  [glView MakeCurrent];
}

- (void) BeginSession
{
  [glView BeginSession];
}

- (void) EndSession
{
  [glView EndSession];
}


@end///< nglUIWindow




////////////////////////////////////////////////////////////////////////////////////// EAGLVIEW:
@implementation EAGLView

// You must implement this method
+ (Class)layerClass
{
  return [CAEAGLLayer class];
}

//The EAGL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:
- (id)initWithFrame:(CGRect)rect replacing:(EAGLView*) original
{
  NSLog(@"new EAGLView (%f,%f %fx%f)\n", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
  context = nil;
  backingWidth = 0;
  backingHeight = 0;
  angle = 0;
  defaultFramebuffer = 0;
  colorRenderbuffer = 0;
  
  rect.origin.x = 0;
  rect.origin.y = 0;
  if ((self = [super initWithFrame:rect]))
  {
    // Get the layer
    CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
    
    eaglLayer.opaque = TRUE;
    eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithBool:TRUE], kEAGLDrawablePropertyRetainedBacking,
                                    kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat,
                                    nil];
    
    EAGLSharegroup* group = nil;
    if (original != nil)
      group = [original getSharegroup];
    
    if (group)
      context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1 sharegroup: group];
    else
      context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
    
    if (!context || ![EAGLContext setCurrentContext:context])
    {
      [self release];
      return nil;
    }
    
    // Create default framebuffer object. The backing will be allocated for the current layer in -resizeFromLayer
    glGenFramebuffersOES(1, &defaultFramebuffer);
    glGenRenderbuffersOES(1, &colorRenderbuffer);
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, defaultFramebuffer);
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
    glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, colorRenderbuffer);
  }
  
  return self;
}

- (EAGLSharegroup*)getSharegroup
{
  return [[self context] sharegroup];
}

- (void)layoutSubviews
{
  [self resizeFromLayer:(CAEAGLLayer*)self.layer];
}


- (void)dealloc
{
  // Tear down GL
  if (defaultFramebuffer)
  {
    glDeleteFramebuffersOES(1, &defaultFramebuffer);
    defaultFramebuffer = 0;
  }
  
  if (colorRenderbuffer)
  {
    glDeleteRenderbuffersOES(1, &colorRenderbuffer);
    colorRenderbuffer = 0;
  }
  
  // Tear down context
  if ([EAGLContext currentContext] == context)
    [EAGLContext setCurrentContext:nil];
  
  [context release];
  context = nil;
  
  
  [super dealloc];
}

- (EAGLContext*)context
{
  return context;
}

#if 0
- (void)render
{
  // Replace the implementation of this method to do your own custom drawing
  
#define SIZE 100
  static const GLfloat squareVertices[] = {
    0,  0,
    SIZE,  0,
    0,   SIZE,
    SIZE,   SIZE,
  };
  
  static const GLubyte squareColors[] = {
    255, 255,   0, 255,
    0,   255, 255, 255,
    0,     0,   0,   0,
    255,   0, 255, 255,
  };
  
  static const GLfloat squareTex[] = {
    0, 0,
    1, 0,
    0, 1,
    1, 1
  };
  
  static float transY = 0.0f;
  
  // This application only creates a single context which is already set current at this point.
  // This call is redundant, but needed if dealing with multiple contexts.
  [EAGLContext setCurrentContext:context];
  
  // This application only creates a single default framebuffer which is already bound at this point.
  // This call is redundant, but needed if dealing with multiple framebuffers.
  glBindFramebufferOES(GL_FRAMEBUFFER_OES, defaultFramebuffer);
  glViewport(0, 0, backingWidth, backingHeight);
  
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity();
  float w = backingWidth;
  float h = backingHeight;
  if (angle == 270 || angle == 90)
  {
    w = backingHeight;
    h = backingWidth;
  }
  
  glRotatef(angle, 0.f,0.f,1.f);
  glTranslatef(-1.0f, 1.0f, 0.0f);
  glScalef(2.0f/w, -2.0f/h, 1.0f);
  
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity();
  
  glClearColor(0.5f, 0.5f, 0.5f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);
  
  glVertexPointer(2, GL_FLOAT, 0, squareVertices);
  glEnableClientState(GL_VERTEX_ARRAY);
  glColorPointer(4, GL_UNSIGNED_BYTE, 0, squareColors);
  glEnableClientState(GL_COLOR_ARRAY);
  glTexCoordPointer(2, GL_FLOAT, 0, squareTex);
  glEnableClientState(GL_TEXTURE_COORD_ARRAY);
  
  glEnable(GL_BLEND);
  glBlendFunc(GL_ONE, GL_SRC_COLOR);
  glDisable(GL_TEXTURE_2D);
  
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  
  glLoadIdentity();
  glTranslatef(w - SIZE, 0, 0.0f);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 3);
  
  glLoadIdentity();
  glTranslatef(w - SIZE, h - SIZE, 0.0f);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 3);
  
  glLoadIdentity();
  glTranslatef(0, h - SIZE, 0.0f);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 3);
  
  int err = glGetError();
  if (!texture)
  {
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    const unsigned char data[] =
    {
      0,0,0,255,          255,255,255,255,
      255,255,255,255,    0,0,0,255
    };
    
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 2, 2, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
    err = glGetError();
    
    //glTexEnvf( GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE );
    glTexEnvf( GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE );
    err = glGetError();
    
    
    // the texture wraps over at the edges (repeat)
    glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT );
    glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT );
    
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST); 
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
    err = glGetError();
  }
  else
  {
    glBindTexture(GL_TEXTURE_2D, texture);
    err = glGetError();
  }
  err = glGetError();
  
  glEnable(GL_TEXTURE_2D);
  //glDisableClientState(GL_COLOR_ARRAY);
  
  glLoadIdentity();
  glTranslatef((w - SIZE) / 2, (h - SIZE) / 2, 0.0f);
  //glDrawArrays(GL_LINE_LOOP, 0, 3);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  
  // This application only creates a single color renderbuffer which is already bound at this point.
  // This call is redundant, but needed if dealing with multiple renderbuffers.
  glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
  [context presentRenderbuffer:GL_RENDERBUFFER_OES];
}
#endif

- (BOOL)resizeFromLayer:(CAEAGLLayer *)layer
{	
  // Allocate color buffer backing based on the current layer size
  glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
  [context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:layer];
  glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
  glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);
  
  if (glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) != GL_FRAMEBUFFER_COMPLETE_OES)
  {
    NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES));
    return NO;
  }
  
  printf("Resize frame buffer: %d x %d\n", backingWidth, backingHeight);
  
  // Angle:
  UIDevice* pUIDev = [UIDevice currentDevice];
  unsigned int orientation = pUIDev.orientation;
  
  switch (orientation)
  {
    case UIDeviceOrientationUnknown:
    case UIDeviceOrientationFaceUp:
    case UIDeviceOrientationFaceDown:
      angle = 0;
      break;
    case UIDeviceOrientationPortrait:
      angle = 0;
      break;
    case UIDeviceOrientationPortraitUpsideDown:
      angle = 180;
      break;
    case UIDeviceOrientationLandscapeLeft:
      angle = 270;
      break;
    case UIDeviceOrientationLandscapeRight:
      angle = 90;
      break;
    default:
      break;
  }
  
  return YES;
}

- (void) MakeCurrent
{
  [EAGLContext setCurrentContext:context];
}

- (void) BeginSession
{
  [EAGLContext setCurrentContext:context];
  glBindFramebufferOES(GL_FRAMEBUFFER_OES, defaultFramebuffer);
}

- (void) EndSession
{
  glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
  [context presentRenderbuffer:GL_RENDERBUFFER_OES];
}




@end


/////////////////////////////////////////////////////////////////////////////////////////////////// NGL WINDOW:



/*
 * OS specific info
 */

nglWindow::OSInfo::OSInfo()
{
  mpUIWindow = NULL;
}

/*
 * Constructors
 */

nglWindow::nglWindow (uint Width, uint Height, bool IsFullScreen)
{
  mpUIWindow = NULL;
  nglContextInfo context; // Get default context
  nglWindowInfo info(Width, Height, IsFullScreen);
  InternalInit (context, info, NULL); 
}

nglWindow::nglWindow (const nglContextInfo& rContext, const nglWindowInfo& rInfo, const nglContext* pShared)
{
  mpUIWindow = NULL;
  InternalInit (rContext, rInfo, pShared);
}

void nglWindow::InternalInit (const nglContextInfo& rContext, const nglWindowInfo& rInfo, const nglContext* pShared)
{
  mState = eHide;
  mAngle = 0;

  SetError (NGL_WINDOW_ENONE);
  SetEventMask(nglWindow::AllEvents);

  mAutoRotate = true;
  
  for (nglTouchId t = 0; t < _NUI_MAX_TOUCHES_; t++)
  {
    gPressedTouches[t] = false;
    gAvailableTouches.push_back(t);
  }

  mAngle = rInfo.Rotate;
  CGRect rect = [[UIScreen mainScreen] applicationFrame];
  float w, h;
  mWidth = 0;
  mHeight = 0;
  if (mAngle == 270 || mAngle == 90)
  {
    w = rect.size.height;
    h = rect.size.width;
  }
  else
  {
    w = rect.size.width;
    h = rect.size.height;
  }
  

  // Create the actual window
  nglUIWindow* pUIWindow = [[nglUIWindow alloc] initWithFrame: rect andNGLWindow: this];

  mOSInfo.mpUIWindow = pUIWindow;
  mpUIWindow = pUIWindow;

  // Build
  
  // Enable multitouch
  [pUIWindow setMultipleTouchEnabled: YES];
  
  [pUIWindow makeKeyAndVisible];
  
  NGL_LOG(_T("window"), NGL_LOG_INFO, _T("trying to create GLES context"));
  rContext.Dump(NGL_LOG_INFO);
  
  if (rContext.TargetAPI != eTargetAPI_OpenGL)
  {
    // UIKit Implementation only supports OpenGLES renderer so far
    NGL_LOG(_T("window"), NGL_LOG_INFO, _T("bad renderer"));
    NGL_ASSERT(0);
    return;
  }
	
	CGRect r = [(nglUIWindow*)mpUIWindow frame];
	printf("currentFrame: %f, %f - %f, %f\n", r.origin.x, r.origin.y, r.size.width, r.size.height);
	r = [UIScreen mainScreen].applicationFrame;
	printf("applicationFrame: %f, %f - %f, %f\n", r.origin.x, r.origin.y, r.size.width, r.size.height);
	
	SetSize(w, h);
	
  glClearColor(0, 0, 0, 1);
  glClear(GL_COLOR_BUFFER_BIT);
  
//  [pUIWindow UpdateOrientation];

/* Ultra basic UIKit view integration on top of nuiWidgets
  UIWebView* pWebView = [[UIWebView alloc] initWithFrame: CGRectMake(50, 50, 200, 200)];
	[pUIWindow addSubview: pWebView];
	pWebView.hidden = NO;
  NSURL* pURL = [[NSURL alloc] initWithString: @"http://libnui.net"];
  NSURLRequest* pReq = [[NSURLRequest alloc] initWithURL: pURL];
  [pWebView loadRequest: pReq];
 */
}

nglWindow::~nglWindow()
{
}


/*
 * All services
 */

void nglWindow::SetState (StateChange State)
{
  if (mState == State)
    return;

  //  static bool was_mapped = false;
  //  static int last_x, last_y;
  UIApplication* pApp = [UIApplication sharedApplication];

  switch (State)
  {
    case eHide:
      [pApp setStatusBarHidden:FALSE animated:TRUE];
      break;
    case eShow:
      [pApp setStatusBarHidden:FALSE animated:TRUE];
      break;
    case eMinimize:
      [pApp setStatusBarHidden:FALSE animated:TRUE];
      break;
	case eMaximize:
    {
      [pApp setStatusBarHidden:TRUE animated:TRUE];
    }
    break;
  };
  [(nglUIWindow*)mpUIWindow UpdateOrientation];
}

nglWindow::StateInfo nglWindow::GetState() const
{
  return eVisible;
}

void nglWindow::GetSize (uint& rWidth, uint& rHeight) const
{
  rWidth  = mWidth;
  rHeight = mHeight;
}

uint nglWindow::GetWidth () const
{
	return mWidth;
}

uint nglWindow::GetHeight () const
{
  return mHeight;
}

bool nglWindow::SetSize (uint Width, uint Height)
{
  NGL_OUT(_T("nglWindow::SetSize(%d, %d)\n"), Width, Height);
  mWidth  = Width;
  mHeight = Height;
  CallOnResize(Width, Height);
  return false;
}

void nglWindow::GetPosition (int& rXPos, int& rYPos) const
{
  // FIXME
}

bool nglWindow::SetPosition (int XPos, int YPos)
{
  // FIXME
  return false;
}

nglString nglWindow::GetTitle() const
{
  return _T("UIKit Window\n");
}

void nglWindow::SetTitle (const nglString& rTitle)
{
}

bool nglWindow::IsKeyDown (nglKeyCode Key) const
{
  return false;
}

void nglWindow::GetMouse (nglMouseInfo& rMouseInfo, bool Local) const
{
}

const nglWindow::OSInfo* nglWindow::GetOSInfo() const
{
  return &mOSInfo;
}

void nglWindow::BeginSession()
{
#ifdef _DEBUG_WINDOW_
  NGL_LOG(_T("window"), NGL_LOG_INFO, _T("BeginSession\n"));
#endif
  //  MakeCurrent();
  NGL_ASSERT(mpUIWindow);
  [mpUIWindow BeginSession];
}

void nglWindow::EndSession()
{
#ifndef __NOGLCONTEXT__

#ifdef _DEBUG_WINDOW_
  NGL_LOG(_T("window"), NGL_LOG_INFO, _T("EndSession\n"));
#endif
	
  NGL_ASSERT(mpUIWindow);
  [mpUIWindow EndSession];
#endif
}

bool nglWindow::MakeCurrent() const
{
  NGL_ASSERT(mpUIWindow);
  [mpUIWindow MakeCurrent];

  return true;
}

void nglWindow::Invalidate()
{
  [(nglUIWindow*)mpUIWindow invalidate];
}

bool nglWindow::SetCursor(nuiMouseCursor Cursor)
{
///< No Cursor relevance here
  return true;
}

nuiMouseCursor nglWindow::GetCursor() const
{
///< No Cursor relevance here
  return eCursorNone;
}

nglWindow::EventMask nglWindow::GetEventMask() const
{
  return mEventMask;
}

void nglWindow::SetEventMask(EventMask Events)
{
  mEventMask = Events;
}

bool nglWindow::GetResolution(float& rHorizontal, float& rVertical) const
{
  rHorizontal = rVertical = 72.f;
  return false;
}


void nglWindow::EnterModalState()
{
  SetState(eShow);
  NGL_OUT(_T("nglWindow::EnterModalState NOT IMPLENTED YET!"));
//  NGL_ASSERT(!"Not Implemented");
}

void nglWindow::ExitModalState()
{
  NGL_OUT(_T("nglWindow::ExitModalState NOT IMPLENTED YET!"));
//  NGL_ASSERT(!"Not Implemented");  
}

void nglWindow::StartTextInput(int32 X, int32 Y, int32 W, int32 H)
{
  [(nglUIWindow*)mpUIWindow showKeyboard];
}

void nglWindow::EndTextInput()
{
  [(nglUIWindow*)mpUIWindow hideKeyboard];
}

bool nglWindow::IsEnteringText() const
{
  //[(nglUIWindow*)mpUIWindow frame]
  return false;
}

/// Drag and Drop:
bool nglWindow::Drag(nglDragAndDrop* pDragObject)
{
  return false;
}

nglDropEffect nglWindow::OnCanDrop(nglDragAndDrop* pDragObject, int X,int Y, nglMouseInfo::Flags Button)
{
  return eDropEffectNone;
}

void nglWindow::OnDragEnter()
{
}

void nglWindow::OnDragLeave()
{
}

void nglWindow::OnDragRequestData(nglDragAndDrop* pDragObject, const nglString& rMimeType)
{
}

void nglWindow::OnDragStop(bool canceled)
{
}

void nglWindow::OnDropped(nglDragAndDrop* pDragObject, int X,int Y, nglMouseInfo::Flags Button)
{
}

