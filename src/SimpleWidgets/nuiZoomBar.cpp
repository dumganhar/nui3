/*
 *  nuiZoomBar.cpp
 *  nui3
 *
 *  Created by campion matthieu on 10/5/07.
 *  Copyright 2007 __MyCompanyName__. All rights reserved.
 *
 */

#include "nui.h"
#include "nuiZoomBar.h"

nuiZoomBar::nuiZoomBar(nuiOrientation Orientation, const nuiRange& rRange, float SideSize, float MiddleSize, nuiSize PageSizeMin, nuiWidgetPtr pThumb)
: nuiScrollBar(Orientation, rRange, pThumb),
mPageSizeMin(PageSizeMin),
mUnzoomAfterBound(false)
{
 SetObjectClass(_T("nuiZoomBar")); 

  
  SetThumbSideSize(SideSize);
  SetThumbMiddleSize(MiddleSize);
}

nuiZoomBar::~nuiZoomBar()
{
  
}


bool nuiZoomBar::Draw(nuiDrawContext* pContext)
{
  nuiScrollBar::Draw(pContext);
  
  pContext->DrawLine(mThumbRect.Left() + mThumbSideSize, mThumbRect.mBottom, mThumbRect.Left() + mThumbSideSize, mThumbRect.mTop);
  pContext->DrawLine(mThumbRect.Right() - mThumbSideSize, mThumbRect.mBottom, mThumbRect.Right() - mThumbSideSize, mThumbRect.mTop);

  
  return true;
}


bool nuiZoomBar::MouseClicked(nuiSize X, nuiSize Y, nglMouseInfo::Flags Button)
{
  mClickX = X;
  mClickY = Y;
  
  if (Button & nglMouseInfo::ButtonLeft)
  {
    mClicked = true;
    Grab();
    Invalidate();
    
    mThumbClicked = false;
    mPageUpClicked = false;
    mPageDownClicked = false;
    if (mOrientation == nuiHorizontal)
    {
      if (X < mThumbRect.Left()) // PageUp
      {
        mTimer.Start(true,true);
        mPageUpClicked = true;
      }
      else if (X > mThumbRect.Right()) // PageDown
      {
        mTimer.Start(true,true);
        mPageDownClicked = true;
      }
      else if (X < mThumbRect.Left() + mThumbSideSize ) // Change Left
      {
        mClickValue = mRange.GetValue();
        mLeftSideClicked = true;
      }
      else if ( X > mThumbRect.Right() - mThumbSideSize) // Change Right
      {
        mClickValue = mRange.GetValue();
        mRightSideClicked = true;
      }
      else
      {
        mClickValue = mRange.GetValue();
        mThumbClicked = true;
      }
    }
    else
    {
      if (Y < mThumbRect.Top()) // PageUp
      {
        mTimer.Start(true,true);
        mPageUpClicked = true;
      }
      else if (Y > mThumbRect.Bottom()) // PageDown
      {
        mTimer.Start(true,true);
        mPageDownClicked = true;
      }
      else if (Y < mThumbRect.Top() + mThumbSideSize ) // Change Top
      {
        mClickValue = mRange.GetValue();
        mRightSideClicked = true;
      }
      else if ( Y > mThumbRect.Bottom() - mThumbSideSize) // Change Bottom
      {
        mClickValue = mRange.GetValue();
        mLeftSideClicked = true;
      }
      else
      {
        mClickValue = mRange.GetValue();
        mThumbClicked = true;
        ThumbPressed();
      }
    }
    return true;
  }
  else if (Button & nglMouseInfo::ButtonWheelUp)
  {
    mRange.Decrement();
    return true;
  }
  else if (Button & nglMouseInfo::ButtonWheelDown)
  {
    mRange.Increment();
    return true;
  }
  return false;
}


bool nuiZoomBar::MouseUnclicked(nuiSize X, nuiSize Y, nglMouseInfo::Flags Button)
{
  if (Button & nglMouseInfo::ButtonLeft)
  {
    mClicked = false;
    
    if (mPageUpClicked || mPageDownClicked)
    {      
      mTimer.Stop();
    }
    else
    {
      ThumbDepressed();
    }
    
    mThumbClicked = false;
    mPageUpClicked = false;
    mPageDownClicked = false;
    mRightSideClicked = false;
    mLeftSideClicked = false;
    Ungrab();
    
    Invalidate();
    return true;
  }
  return false;
  
}


bool nuiZoomBar::MouseMoved(nuiSize X, nuiSize Y)
{
  if (!mThumbClicked && !mLeftSideClicked && !mRightSideClicked)
  {
    if (mOrientation == nuiHorizontal)
    {
      ChangeZoomCursor(X, mThumbRect.Left(), mThumbRect.Right());
    }
    else if (mOrientation == nuiVertical)
    {
      ChangeZoomCursor(Y, mThumbRect.Bottom(), mThumbRect.Top());
    }    
  }  
  
  
  
  nuiSize x,y;
  x = X-mClickX;
  y = Y-mClickY;
  
  nuiSize length = mRange.GetRange();
  nuiSize start=(mClickValue/length);
  nuiSize movement;
  
  if (mThumbClicked)
  {
    if (mOrientation == nuiHorizontal)
    {
      movement = x;
      start +=movement/mRect.GetWidth();
    }
    else
    {
      movement = y;
      start +=movement/mRect.GetHeight();
    }
    mRange.SetValue(start*length);
    return true;
  }
  else if (mLeftSideClicked)
  {
    if (mOrientation == nuiHorizontal)
    {
      UpdateDownBound(x);
      
      mClickX = X;
      mClickY = Y;
      return true;
    }
    
    if (mOrientation == nuiVertical)
    {
      UpdateDownBound(y);
      
      mClickX = X;
      mClickY = Y;
      return true;
    }
  }
  else if (mRightSideClicked)
  {
    if (mOrientation == nuiHorizontal)
    {
      UpdateUpBound(x);
      
      mClickX = X;
      mClickY = Y;
      return true;
    }
    
    if (mOrientation == nuiVertical)
    {
      UpdateUpBound(y);
      
      mClickX = X;
      mClickY = Y;
      return true;
    }
  }
  
  return true;  
}


void nuiZoomBar::UpdateUpBound(nuiSize move)
{
  nuiSize length = mRange.GetRange();
  nuiSize pageSize = mRange.GetPageSize()/length;
  
  pageSize += move/mRect.GetWidth();
  
  if (pageSize < 0.0)
    pageSize = 0.0;
  if (pageSize > 1.0)
    pageSize = 1.0;
  
  double Page = pageSize*length;
  double Value = mRange.GetValue();
  
  if (Value + Page > mRange.GetMaximum())
  {
    if (IsUnZoomAfterBoundEnabled())
    {
      Value -= (Value + Page - mRange.GetMaximum());
    }
    else
    {
      Page = mRange.GetMaximum() - Value;
    }
  }
  
  if (Page <= mPageSizeMin)
  {
    Page = mPageSizeMin;
  }
  
  mRange.SetValueAndSize(Value, Page);
}

void nuiZoomBar::UpdateDownBound(nuiSize move)
{
  nuiSize prevEnd = mRange.GetValue() + mRange.GetPageSize();
    
  nuiSize length = mRange.GetRange();
  nuiSize start=(mClickValue/length);
  
  start += move/mRect.GetWidth();
  
  double Value = start * length;
  nuiSize Page = prevEnd - Value;
  
  nuiSize min = mRange.GetMinimum();
  if (Value < min)
  {
    if (IsUnZoomAfterBoundEnabled())
    {
      Page += min - Value;
      Value = min;
      
    }
    else
    {
      Value = min;
      Page = prevEnd - min;
    }
  }
  
  mClickValue = Value;
  
  if (Page < 0.0)
    Page = 0.0;
  if (Page > mRange.GetRange())
    Page = mRange.GetRange();

  if (Page <= mPageSizeMin)
  {
    Page = mPageSizeMin;
    Value = prevEnd - Page;
  }
  
  mRange.SetValueAndSize(Value, Page);
}


nuiSize nuiZoomBar::GetPageSizeMin() const
{
  return mPageSizeMin;
}

void nuiZoomBar::SetPageSizeMin(nuiSize min)
{
  mPageSizeMin = MAX(min, 0.0);
}

bool nuiZoomBar::IsUnZoomAfterBoundEnabled()
{
  return mUnzoomAfterBound;
}

void nuiZoomBar::EnableUnzoomAfterBound(bool set)
{
  mUnzoomAfterBound = set;
}


void nuiZoomBar::ChangeZoomCursor(nuiSize coord, nuiSize DownLimit, nuiSize UpLimit)
{
  if (coord > DownLimit + mThumbSideSize && coord < UpLimit - mThumbSideSize) // Hover Center
  {
    SetMouseCursor(eCursorHand);
  }
  
  else if (coord >= DownLimit && coord < DownLimit + mThumbSideSize ) //Hover Left Handler
  {
    if (mRange.GetPageSize() == mPageSizeMin)
    {
      if (mOrientation == nuiHorizontal)
        SetMouseCursor(eCursorResizeW);
      else if (mOrientation == nuiVertical)
        SetMouseCursor(eCursorResizeS);
    }
    else if (mRange.GetValue() == mRange.GetMinimum() && mRange.GetPageSize() == mRange.GetRange())
    {
      if (mOrientation == nuiHorizontal)
        SetMouseCursor(eCursorResizeE);
      else if (mOrientation == nuiVertical)
        SetMouseCursor(eCursorResizeN);
    }
    else if (mRange.GetValue() == mRange.GetMinimum() && !IsUnZoomAfterBoundEnabled())
    {
      if (mOrientation == nuiHorizontal)
        SetMouseCursor(eCursorResizeE);
      else if (mOrientation == nuiVertical)
        SetMouseCursor(eCursorResizeN);
    }
    else
    {
      if (mOrientation == nuiHorizontal)
        SetMouseCursor(eCursorResizeWE);
      else if (mOrientation == nuiVertical)
        SetMouseCursor(eCursorResizeNS);
    }
  
  }
  else if (coord <= UpLimit && coord > UpLimit - mThumbSideSize) //Hover Right Handler
  {
    if (mRange.GetPageSize() == mPageSizeMin)
    {
      if (mOrientation == nuiHorizontal)
        SetMouseCursor(eCursorResizeE);
      else if (mOrientation == nuiVertical)
        SetMouseCursor(eCursorResizeN);
    }
    else if (mRange.GetValue() == mRange.GetMinimum() && mRange.GetPageSize() == mRange.GetRange())
    {
      if (mOrientation == nuiHorizontal)
        SetMouseCursor(eCursorResizeW);
      else if (mOrientation == nuiVertical)
        SetMouseCursor(eCursorResizeS);
    }
    else if (mRange.GetValue() + mRange.GetPageSize() == mRange.GetMaximum() && !IsUnZoomAfterBoundEnabled())
    {
      if (mOrientation == nuiHorizontal)
        SetMouseCursor(eCursorResizeW);
      else if (mOrientation == nuiVertical)
        SetMouseCursor(eCursorResizeS);
    }
    else
    {
      if (mOrientation == nuiHorizontal)
        SetMouseCursor(eCursorResizeWE);
      else if (mOrientation == nuiVertical)
        SetMouseCursor(eCursorResizeNS);
    }
  }
    else
    {
      SetMouseCursor(eCursorArrow);
    }
  
}
