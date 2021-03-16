' Copyright (c) 2019 true[X], Inc. All rights reserved.
'-----------------------------------------------------------------------------------------------------------
' ContentFlow
'-----------------------------------------------------------------------------------------------------------
' Uses the IMA SDK to initialize and play a video stream with dynamic ad insertion (DAI).
'
' NOTE: Expects m.global.streamInfo to exist with the necessary video stream information.
'
' Member Variables:
' See setupScopedVariables
'-----------------------------------------------------------------------------------------------------------

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
    m.port = createObject("roMessagePort")  ' Event port.  Must be used for events due to render/task thread scoping
    m.adFacade = m.top.adFacade  ' Hold reference to the component to put the adRenderer onto
    m.skipAds = false   ' Flag to skip non-truex ads
    m.lastPosition = 0  ' Tracks last position, primarily for seeking purposes
    m.videoPlayer = invalid
    m.raf = invalid
    m.truexAd = invalid ' TODO: See if this can be removed
    m.currentAdPod = invalid ' Current ad pod in use or processing
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

    raf.SetDebugOutput(true) 'debugging
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
    playContentStream() ' Will handle playing a preroll if it exists per above

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
            exitContentStream()
            end if
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
        playContentStream()
    else if eventType = types.USERCANCELSTREAM
        exitContentStream()
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
        firstAd = ads.ads[0] 'Assume truex can only be first ad in a pod

        if isTruexAd(firstAd)
            m.truexAd = firstAd
            m.truexAd.adParameters = parseJSON(m.truexAd.adParameters)
            m.truexAd.renderSequence = ads.renderSequence
            
            ' Need to delete the ad from the pod which is referenced by raf so it plays
            ' ads from the correct index when resulting in non-truex flows (eg. opt out)
            ' If it is not deleted, this pod will attempt to play the truex ad placeholder
            ' when it is passed into raf.showAds()
            ads.ads.delete(0)

            playTrueXAd()
            resumePlayback = false
        else ' Non-TrueX ads
            hideContentStream()
            watchedAd = m.raf.showAds(ads, invalid, m.adFacade) ' Takes thread ownership until complete or exit

            if watchedAd
                resumePlayback = true 
            else
                resumePlayback = false
                exitContentStream() 
            end if
        end if
    end if

    return resumePlayback
end function

function isTruexAd(ad) as Boolean
    if ad.adParameters <> invalid AND ad.adserver <> invalid AND ad.adserver.instr(0, "get.truex.com/") > 0 then return true

    return false
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

    hideContentStream()

    ? "TRUE[X] >>> PlaybackTask::playTrueXAd() - starting TruexAdRenderer..."
    m.adRenderer.action = { type: "start" }
    m.adRenderer.focusable = true
    m.adRenderer.SetFocus(true)
end sub

sub playContentStream()
    cleanUpAdRenderer()

    if m.skipAds AND m.currentAdPod <> invalid then
        m.currentAdPod.viewed = true
        m.currentAdPod = invalid
        m.skipAds = false
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

sub hideContentStream()
    m.videoPlayer.control = "stop"
    m.videoPlayer.visible = false
end sub

sub exitContentStream()  
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