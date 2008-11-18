/*
 NUI3 - C++ cross-platform GUI framework for OpenGL based applications
 Copyright (C) 2002-2003 Sebastien Metrot
 
 licence: see nui3/LICENCE.TXT
 */

#include "nuiAudioDevice.h"
#include "nglThread.h"
#include <AudioToolbox/AudioToolbox.h>



class nuiAudioDevice_AudioQueue : public nuiAudioDevice
{
public:
  nuiAudioDevice_AudioQueue();
  
  virtual ~nuiAudioDevice_AudioQueue();
  
  virtual bool Open(std::vector<uint32>& rInputChannels, std::vector<uint32>& rOutputChannels, double SampleRate, uint32 BufferSize, nuiAudioProcessFn pProcessFunction);
  
  virtual bool Close();
  
  
protected:
  void EnumSampleRates();
  void EnumBufferSizes();
  nglString GetChannelName(bool IsInput, uint32 index) const;
  
  nuiAudioProcessFn mAudioProcessFn;
  std::vector<uint32> mActiveInputChannels;
  std::vector<uint32> mActiveOutputChannels;
  
  std::vector<std::vector<float> > mInputSamples;
  std::vector<std::vector<float> > mOutputSamples;
  
  std::vector<const float*> mInputBuffers;
  std::vector<float*> mOutputBuffers;
  
  double mSampleRate;
  uint32 mBufferSize;
  
  std::vector<std::pair<uint32, uint32> > mInMap;
  std::vector<std::pair<uint32, uint32> > mOutMap;

  AudioQueueRef mOutQueue;
  AudioQueueRef mInQueue;
  
  static void OutputCallback(void* inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer);
};




class nuiAudioDeviceAPI_AudioQueue : public nuiAudioDeviceAPI
{
public:
  nuiAudioDeviceAPI_AudioQueue();
  virtual ~nuiAudioDeviceAPI_AudioQueue();
  
  virtual uint32 GetDeviceCount() const;
  
  virtual nuiAudioDevice* GetDevice(uint32 index);
  virtual nuiAudioDevice* GetDevice(const nglString& rDeviceName);
  virtual nglString GetDeviceName(uint32 index) const;
  virtual nuiAudioDevice* GetDefaultOutputDevice();
  virtual nuiAudioDevice* GetDefaultInputDevice();
};

extern nuiAudioDeviceAPI_AudioQueue AudioQueueAPI;