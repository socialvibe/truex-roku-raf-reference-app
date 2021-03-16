Library "Roku_Ads.brs" ' Must be initialized in the task (or main) thread

sub init()
  ? "TRUE[X] >>> PlaybackTask::init()"
  m.top.functionName = "setup"
end sub

sub setup() 
  setupScopedVariables()
  setupVideo()
  setupRaf()
  setupEvents()
  initPlayback()
end sub

sub setupScopedVariables()
  m.port = createObject("roMessagePort")
  m.adFacade = m.top.adFacade
  m.skipAds = false
  m.lastPosition = 0
  m.videoPlayer = invalid
  m.raf = invalid
  m.truexAd = invalid
  m.currentAdPod = invalid
end sub

sub setupVideo()
  ? "TRUE[X] >>> setupVideo()"

  videoPlayer = m.top.video
  videoContent = createObject("roSGNode", "ContentNode")

  videoContent.url = "http://ctv.truex.com/assets/reference-app-stream-no-ads-720p.mp4"
  videoContent.length = 22 * 60

  videoContent.title = "The true[X] Employee Experience"
  videoContent.streamFormat = "mp4"
  videoContent.playStart = 0

  videoPlayer.content = videoContent
  videoPlayer.SetFocus(true)
  videoPlayer.visible = true
  videoPlayer.observeField("position", m.port)
  videoPlayer.EnableCookies()

  m.videoPlayer = videoPlayer
end sub

sub setupRaf()
  ? "TRUE[X] >>> setupRaf()"
  raf = Roku_Ads()
  raf.enableAdMeasurements(true)
  raf.setContentGenre("Entertainment")
  raf.setContentId("TrueXSample")

  raf.SetDebugOutput(false) 'debugging
  raf.SetAdPrefs(false)

  adUrl = m.top.adUrl
  if adUrl = invalid OR adUrl = ""
    adUrl = "pkg:/res/adpods/vmap-truex.xml" ' Preroll + Midroll Truex experience
    ' adUrl = "pkg:/res/adpod/truex-pod-preroll.xml"  ' Can check individual vast pods
  end if 
  raf.setAdUrl(adUrl)

  m.raf = raf
end sub

sub setupEvents()
  m.top.observeField("exitPlayback", m.port)
end sub

sub initPlayback()
  ? "TRUE[X] >>> initPlayback()"

  m.currentAdPod = getPreroll()
  startPlayback() ' Will handle playing a preroll if it exists per above

  while(true)
    msg = Wait(0, m.port)
    msgType = type(msg)

    ' ? "event type:" msgType
    if msgType = "roSGNodeEvent"
      field = msg.getField()
      ' ? "roSGNodeEvent msg.getField()" field
      if field = "position" then 
        onPositionChanged(msg)
      else if field = "event" then
        onTrueXEvent(msg)
      else if field = "exitPlayback"
        exitPlayback()
      end if
      ' TODO: Video complete event
    end if
  end while
end sub

sub onPositionChanged(event)
  m.lastPosition = event.getData()

  ads = m.raf.getAds(event)
  handleAds(ads)
end sub

sub onTruexEvent(event)
  data = event.getData()
  eventType = data.type

  ? "TRUE[X] >>> PlaybackTask::onTrueXEvent(): " eventType

  types = {
    "ADSTARTED": "adStarted",
    "ADCOMPLETED": "adCompleted"
    "ADPOSITION": "adPosition",
    "ADERROR": "adError",
    "ADFREEPOD": "adFreePod"
    "NOADSAVAILABLE": "noAdsAvailable",
    "OPTIN": "optIn",
    "OPTOUT": "optOut",
    "USERCANCEL": "userCancel",
    "USERCANCELSTREAM": "userCancelStream",
    "SKIPCARDSHOWN": "skipCardShown"
  }

  if eventType = types.ADFREEPOD
    m.skipAds = true
  else if eventType = types.ADCOMPLETED OR eventType = types.NOADSAVAILABLE OR eventType = types.ADERROR
    startPlayback()
  else if eventType = types.USERCANCELSTREAM
    exitPlayback()
  end if
end sub

function getPreroll() as Object
  ads = m.raf.getAds()
  if ads = invalid then return false
  
  result = invalid
  for each adPod in ads
    if adPod.rendersequence = "preroll"
      result = adPod
      exit for
    end if
  end for

  return result
end function

function handleAds(ads) as Boolean
  resumePlayback = true

  if ads <> invalid AND ads.ads.count() > 0
    m.currentAdPod = ads
    firstAd = ads.ads[0] 'Assume truex can only be first ad

    if firstAd.adParameters <> invalid
      m.truexAd = firstAd
      m.truexAd.adParameters = parseJSON(m.truexAd.adParameters)
      m.truexAd.renderSequence = ads.renderSequence
      ads.ads.delete(0) ' Removes it from certain use cases due to raf

      playTrueXAd()
      resumePlayback = false
    ' else if firstAd.companionAds <> invalid
      ' m.truexAd.adParameters = ' TODO: CompanionAd Tag handling.  Parse to valid TAR format
      ' m.truexAd.renderSequence = ads.renderSequence
      ' ads.ads.delete(0)
    else ' Non-TrueX ads
      hidePlayback()
      watchedAd = m.raf.showAds(ads, invalid, m.adFacade) 'Takes thread ownership until complete or exit

      if watchedAd
        resumePlayback = true 
      else
        resumePlayback = false
        exitPlayback() 
      end if
    end if
  end if

  return resumePlayback
end function

sub playTrueXAd()
    ? "TRUE[X] >>> PlaybackTask::playTrueXAd() - instantiating TruexAdRenderer ComponentLibrary..."

    ' instantiate TruexAdRenderer and register for event updates
    m.adRenderer = m.top.adFacade.createChild("TruexLibrary:TruexAdRenderer")
    m.adRenderer.observeFieldScoped("event", m.port)

    tarInitAction = {
      type: "init",
      adParameters: m.truexAd.adParameters,
      supportsUserCancelStream: true, ' enables cancelStream event types, disable if Channel does not support
      slotType: ucase(m.truexAd.rendersequence),
      logLevel: 1, ' Optional parameter, set the verbosity of true[X] logging, from 0 (mute) to 5 (verbose), defaults to 5
      channelWidth: 1920, ' Optional parameter, set the width in pixels of the channel's interface, defaults to 1920
      channelHeight: 1080 ' Optional parameter, set the height in pixels of the channel's interface, defaults to 1080
    }
    ? "TRUE[X] >>> PlaybackTask::playTrueXAd() - initializing TruexAdRenderer with action=";tarInitAction
    m.adRenderer.action = tarInitAction

    hidePlayback()

    ? "TRUE[X] >>> PlaybackTask::playTrueXAd() - starting TruexAdRenderer..."
    m.adRenderer.action = { type: "start" }
    m.adRenderer.focusable = true
    m.adRenderer.SetFocus(true)
end sub

sub startPlayback()
    cleanUpAdRenderer()

    if m.skipAds AND m.currentAdPod <> invalid then
      m.currentAdPod.viewed = true
      m.currentAdPod = invalid
    end if

    ' Check if we need to play other (non-truex) ads
    play = handleAds(m.currentAdPod)

    if play
      m.videoPlayer.visible = true
      if (m.lastPosition > 0) m.videoPlayer.seek = m.lastPosition
      m.videoPlayer.control = "play"
      m.videoPlayer.setFocus(true)
    end if
end sub

sub hidePlayback()
    m.videoPlayer.control = "stop"
    m.videoPlayer.visible = false
end sub

sub exitPlayback()  
  cleanUpAdRenderer()
  if m.videoPlayer <> invalid then m.videoPlayer.control = "stop"

  m.top.playerDisposed = true
end sub

sub cleanUpAdRenderer()
  ? "TRUE[X] >>> PlaybackTask::cleanUpAdRenderer(): "
  if m.adRenderer <> invalid then
      m.adRenderer.SetFocus(false)
      m.adRenderer.unobserveFieldScoped("event")
      m.top.removeChild(m.adRenderer)
      m.adRenderer.visible = false
      m.adRenderer = invalid
  end if
end sub