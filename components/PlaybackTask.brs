Library "Roku_Ads.brs" ' Must be initialized in the task (or main) thread

sub init()
  ? "TRUE[X] >>> PlaybackTask::init()"
  m.top.functionName = "setup"
end sub

sub setup() 
  m.port = createObject("roMessagePort")
  m.adFacade = m.top.adFacade

  setupVideo()
  setupRaf()
  startPlayback()
end sub

sub setupVideo()
  ? "TRUE[X] >>> setupVideo()"

  m.videoPlayer = m.top.video

  videoContent = CreateObject("roSGNode", "ContentNode")

  ' videoContent.url = "http://development.scratch.truex.com.s3.amazonaws.com/roku/simon/roku-reference-app-stream-med.mp4"
  videoContent.url = "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4"
  videoContent.title = "video title"
  videoContent.streamFormat = "mp4"
  videoContent.length = 600

  videoContent.playStart = 0

  m.videoPlayer.content = videoContent
  m.videoPlayer.SetFocus(true)
  m.videoPlayer.visible = true
  ' m.videoPlayer.retrievingBar.visible = false
  ' m.videoPlayer.bufferingBar.visible = false
  ' m.videoPlayer.retrievingBarVisibilityAuto = false
  ' m.videoPlayer.bufferingBarVisibilityAuto = false
  m.videoPlayer.observeFieldScoped("position", m.port)
  m.videoPlayer.EnableCookies()
end sub

sub setupRaf()
  ? "TRUE[X] >>> setupRaf()"
  raf = Roku_Ads()
  raf.enableAdMeasurements(true)
  raf.setContentGenre("Entertainment")
  raf.setContentId("TrueXSample")
  ' raf.setContentLength(600)

  raf.SetDebugOutput(false) 'debugging
  raf.SetAdPrefs(false)

  ' adUrl = "pkg:/res/vast.xml"
  adUrl = "pkg:/res/vast-truex.xml"
  raf.setAdUrl(adUrl)
  
  m.adPods = raf.getAds()
  ? "allAds:"  formatJson(m.adPods)

  m.raf = raf
end sub

sub startPlayback()
  ? "TRUE[X] >>> startPlayback()"
  m.videoPlayer.control = "play"

  ' TODO: Handle the preroll case explicitly

  while(true)
    msg = Wait(0, m.port)
    msgType = type(msg)

    ' ? "event type:" msgType

    if msgType = "roSGNodeEvent"
      field = msg.getField()
      ? "roSGNodeEvent" field
      if field = "position" then 
        onPositionChanged(msg)
      else if field = "event" then
        onTrueXEvent(msg)
      end if
    end if
  end while
end sub

sub onPositionChanged(event)
  position = event.getData()
  ? "onPositionChanged: " position

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
    "ADFIRSTQUARTILE": "adFirstQuartile",
    "ADSECONDQUARTILE": "adSecondQuartile",
    "ADTHIRDQUARTILE": "adThirdQuartile",
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

  ' TODO: Various event formats

  if eventType = types.USERCANCEL
    ' TODO: Clean up truex
    ' TODO: Switch to regular ads
    ' TODO: Switch to playback (probably not needed since ads will take care of that)

    m.truexPod.viewed = true ' // This should just go to the next ad break instead.  But to fix the RAF event behaviour, do this for now.
    ' TODO: Remove.  Temporary to improve developer experience
    m.videoPlayer.visible = true
    m.videoPlayer.control = "play"
  end if

  if eventType = types.USERCANCELSTREAM
    cleanUpTruex()
    m.top.playbackEvent = { trigger: "cancelStream" } ' Might want to change this API since this is the flows API to the scene
  end if
end sub

sub cleanUpTruex()
  if m.adRenderer <> invalid then
      m.adRenderer.SetFocus(false)
      m.top.removeChild(m.adRenderer)
      m.adRenderer.visible = false
      m.adRenderer = invalid
  end if
end sub

sub handleAds(ads)
  ? "HandleAds:" formatJSON(ads)
  if ads <> invalid AND ads.ads.count() > 0
    firstPod = ads.ads[0]
  
    ' TODO: Figure out how to get metadata into the Roku ad parser.  AdParameters?
    ' Hacky conditional for now.  
    if firstPod.streams <> invalid AND firstPod.creativeid = "truex-test-id"
      if m.truexPod <> invalid then return

      url = firstPod.streams[0].url
      m.truexPod = ads

      if url.instr(0, "pkg:/") >= 0
        ' See if Roku parses this on their side for real paths
        rawJson = ReadAsciiFile(url).trim()
        truexAd = ParseJson(rawJson)
        truexAd.placement_hash = "74fca63c733f098340b0a70489035d683024440d" 'Placeholder
        m.truexPod.params = truexAd
      else
        m.truexPod.params = {
          vast_config_url: url,
          placement_hash: "74fca63c733f098340b0a70489035d683024440d" 'Placeholder
        }
      end if

      playTrueXAd()
    else ' Non-TrueX ads
      m.videoPlayer.control = "stop"
      m.videoPlayer.visible = false
      watchedAd = m.raf.showAds(ads, invalid, m.adFacade)  ' Takes thread ownership until complete
      m.videoPlayer.visible = true
      m.videoPlayer.control = "play"
    end if
  end if
end sub

sub playTrueXAd()
  launchTruexAd()
end sub

sub launchTruexAd()
    ? "TRUE[X] >>> ContentFlow::launchTruexAd() - instantiating TruexAdRenderer ComponentLibrary..."

    ' instantiate TruexAdRenderer and register for event updates
    m.adRenderer = m.top.adFacade.createChild("TruexLibrary:TruexAdRenderer")
    m.adRenderer.observeFieldScoped("event", m.port)

    ' use the companion ad data to initialize the true[X] renderer
    tarInitAction = {
      type: "init",
      adParameters: m.truexPod.params,
      supportsUserCancelStream: true, ' enables cancelStream event types, disable if Channel does not support
      slotType: ucase(m.truexPod.rendersequence),
      logLevel: 1, ' Optional parameter, set the verbosity of true[X] logging, from 0 (mute) to 5 (verbose), defaults to 5
      channelWidth: 1920, ' Optional parameter, set the width in pixels of the channel's interface, defaults to 1920
      channelHeight: 1080 ' Optional parameter, set the height in pixels of the channel's interface, defaults to 1080
    }
    ? "TRUE[X] >>> ContentFlow::launchTruexAd() - initializing TruexAdRenderer with action=";tarInitAction
    m.adRenderer.action = tarInitAction

    m.videoPlayer.control = "stop"
    m.videoPlayer.visible = false

    ? "TRUE[X] >>> ContentFlow::launchTruexAd() - starting TruexAdRenderer..."
    m.adRenderer.action = { type: "start" }
    m.adRenderer.focusable = true
    m.adRenderer.SetFocus(true)
end sub