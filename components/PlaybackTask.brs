' Copyright (c) 2019 true[X], Inc. All rights reserved.
'-----------------------------------------------------------------------------------------------------------
' PlaybackTask
'-----------------------------------------------------------------------------------------------------------
' Task responsible for handling all responsibilities surrounding RAF, RAF ad integration, TrueX Ad rendering,
' and simple playback behaviours
'
' Member Variables:
' See setupScopedVariables
'-----------------------------------------------------------------------------------------------------------
Library "Roku_Ads.brs" ' Must be managed in a task or render due to a Roku/RAF implementation requirement

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

'-------------------------------------------
' Initialize and setup all member variables for easy reference
'-------------------------------------------
sub setupScopedVariables()
    ? "TRUE[X] >>> setupScopedVariables()"

    m.port = createObject("roMessagePort")  ' Event port.  Must be used for events due to render/task thread scoping
    m.adFacade = m.top.adFacade  ' Hold reference to the component for RAF and Truex ad rendering
    m.skipAds = false   ' Flag to skip non-truex ads
    m.lastPosition = 0  ' Tracks last position, primarily for seeking purposes
    m.videoPlayer = invalid ' Hold reference to player component from render thread
    m.raf = invalid
    m.currentAdPod = invalid ' Current ad pod in use or processing
    m.currentTruexAd = invalid ' Holds ad information, currently for raf tracking
end sub

'-------------------------------------------
' Initialize video player
'-----------------------------------------
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

'-------------------------------------------
' Initialize Roku Ads Framework (RAF)
' Also setup ads via RAF with an ad url
'-----------------------------------------
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
        ' adUrl = "pkg:/res/adpod/truex-pod-preroll.xml"  ' Can check individual vast pods. Always assumed to be a preroll pod by RAF.
    end if 
    raf.setAdUrl(adUrl)

    m.raf = raf
end sub

'-------------------------------------------
' Setup any task based event listening
'-----------------------------------------
sub setupEvents()
    m.top.observeField("exitPlayback", m.port)
end sub

'-------------------------------------------
' Begins the playback experience and starts the event listener loop
' Will be responsible for checking if there is a preroll and to play it before starting playback
'-----------------------------------------
sub initPlayback()
    ? "TRUE[X] >>> initPlayback()"

    m.currentAdPod = getPreroll()
    playContentStream() ' Will handle playing a preroll if it exists per above

    while (true)
        msg = Wait(0, m.port)
        msgType = type(msg)

        if msgType = "roSGNodeEvent"
            field = msg.getField()
            if field = "position" then 
                onPositionChanged(msg)
            else if field = "event" then
                onTrueXEvent(msg)
            else if field = "exitPlayback" then
                exitContentStream()
            end if
        end if
    end while
end sub

'-------------------------------------------
' Stores the last position for player seeking purposes
' Gets ads to process
'
' Params:
'   * event as roAssociativeArray - contains the event data from the port
'-----------------------------------------
sub onPositionChanged(event)
    m.lastPosition = event.getData()

    ads = m.raf.getAds(event)
    handleAds(ads)
end sub

'-------------------------------------------
' Handles all TrueX Library events
' See "types" for the different event types supported and explanations for non obvious cases
'
' Params:
'   * event as roAssociativeArray - contains the TrueX Ad Renderer event data from the port
'-----------------------------------------
sub onTruexEvent(event)
    data = event.getData()
    eventType = data.type

    ? "TRUE[X] >>> PlaybackTask::onTrueXEvent(): " eventType

    types = {
        "ADSTARTED": "adStarted",
        "ADCOMPLETED": "adCompleted"
        "ADPOSITION": "adPosition",
        "ADERROR": "adError",
        "ADFREEPOD": "adFreePod", ' User has earned credit for the engagement.  Can skip past other ads in pod
        "NOADSAVAILABLE": "noAdsAvailable",
        "OPTIN": "optIn",   ' User opts in to choice card
        "OPTOUT": "optOut", ' User opts out of choice card
        "USERCANCELSTREAM": "userCancelStream", ' User exits playback. EG. Typically "back" on choice card
        "SKIPCARDSHOWN": "skipCardShown",
        "VIDEOEVENT": "videoEvent"
    }
    
    rafEventType = invalid
    if eventType = types.ADFREEPOD
        m.skipAds = true
    else if eventType = types.ADCOMPLETED OR eventType = types.NOADSAVAILABLE OR eventType = types.ADERROR
        playContentStream()
    else if eventType = types.USERCANCELSTREAM
        exitContentStream()
    else if eventType = types.VIDEOEVENT
        subType = data.subType

        if subType = "started"
            rafEventType = "Impression"
        else if subType = "firstQuartile"
            rafEventType = "FirstQuartile"
        else if subType = "secondQuartile"
            rafEventType = "Midpoint"
        else if subType = "thirdQuartile"
            rafEventType = "ThirdQuartile"
        else if subType = "completed"
            rafEventType = "Complete"
        else if subType = "paused"
            rafEventType = "Pause"
        else if subType = "resumed"
            rafEventType = "Resume"
        else if subType = "incomplete"
            rafEventType = "Close"
        end if
    end if

    if rafEventType <> invalid
        ' Note the Raf events follow the naming convention as provided by Roku's RAF guidance
        m.raf.fireTrackingEvents(m.currentTruexAd, { type: rafEventType })
    end if
end sub

'-------------------------------------------
' Special ad case where we see if there is a preroll ad to process before starting playback
'
' Return:
'   Preroll AdPod if it exists
'-----------------------------------------
function getPreroll() as Object
    ? "TRUE[X] >>> PlaybackTask::getPreroll(): " 

    ads = m.raf.getAds()
    if ads = invalid then return invalid
    
    result = invalid
    for each adPod in ads
        if adPod.rendersequence = "preroll"
            result = adPod
            exit for
        end if
    end for

    return result
end function

'-------------------------------------------
' General ad handler.  Takes care of seeing for a given pod, to play a truex ad
' or play regular ads
'
' Return:
'   false if playback should not be resumed yet (truex case mainly)
'   true if playback should be resumed (non-ad or certain raf cases)
'-----------------------------------------
function handleAds(ads) as Boolean
    resumePlayback = true

    if ads <> invalid AND ads.ads.count() > 0
        m.currentAdPod = ads
        firstAd = ads.ads[0] 'Assume truex can only be first ad in a pod

        if isTruexAd(firstAd)
            data = {
                adParameters: parseJSON(firstAd.adParameters),
                renderSequence: ads.renderSequence
            }            


            m.currentTruexAd = firstAd
            m.currentTruexAd.adPod = m.currentAdPod
            m.currentTruexAd.position = 0

            ' Need to delete the ad from the pod which is referenced by raf so it plays
            ' ads from the correct index when resulting in non-truex flows (eg. opt out)
            ' If it is not deleted, this pod will attempt to play the truex ad placeholder
            ' when it is passed into raf.showAds()
            ads.ads.delete(0)

            playTrueXAd(data)
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

'-------------------------------------------
' Helper to see if an ad is TrueX
' Checks if there is an <AdParameter> tag, and the ad server is a qa or prod truex domain
'
' Return:
'   true if TrueX, false if other
'-----------------------------------------
function isTruexAd(ad) as Boolean
    prodDomain = "get.truex.com/"
    qaDomain = "qa-get.truex.com/"

    if ad.adParameters <> invalid AND ad.adserver <> invalid AND (ad.adserver.instr(0, prodDomain) > 0 OR ad.adserver.instr(0, qaDomain)) then return true

    return false
end function

'-------------------------------------------
' Handles responsibility of initializing the TrueX Ad Renderer (TAR) and starting the 
' interactive ad experience.  Stops and hides the content video player
' 
' Params:
'   * data as associative array - contains adParameters and renderSequence for TAR
'-----------------------------------------
sub playTrueXAd(data)
    ? "TRUE[X] >>> PlaybackTask::playTrueXAd() - instantiating TruexAdRenderer ComponentLibrary..."

    ' instantiate TruexAdRenderer and register for event updates
    m.adRenderer = m.top.adFacade.createChild("TruexLibrary:TruexAdRenderer")
    m.adRenderer.observeFieldScoped("event", m.port)

    tarInitAction = {
        type: "init",
        adParameters: data.adParameters,
        supportsUserCancelStream: true, ' enables cancelStream event types, disable if Channel does not support
        slotType: ucase(data.rendersequence),
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

'-------------------------------------------
' Handles checking if there are ads to play before starting/resuming playback
' Also always cleans up TAR if able
'-----------------------------------------
sub playContentStream()
    ? "TRUE[X] >>> PlaybackTask::playContentStream(): "

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

'-------------------------------------------
' Hides and stops stream
'-----------------------------------------
sub hideContentStream()
    ? "TRUE[X] >>> PlaybackTask::hideContentStream(): "

    m.videoPlayer.control = "stop"
    m.videoPlayer.visible = false
end sub

'-------------------------------------------
' Cleans up the player to get ready to exit playback
' Bubbles up a message playerDisposed property so invoker knows it is finished cleaning up
'-----------------------------------------
sub exitContentStream()  
    ? "TRUE[X] >>> PlaybackTask::exitContentStream(): "

    cleanUpAdRenderer()
    if m.videoPlayer <> invalid then m.videoPlayer.control = "stop"

    m.top.playerDisposed = true
end sub

'-------------------------------------------
' Cleans up TAR
'-----------------------------------------
sub cleanUpAdRenderer()
    ? "TRUE[X] >>> PlaybackTask::cleanUpAdRenderer(): "
    m.currentTruexAd = invalid
    if m.adRenderer <> invalid then
        m.adRenderer.SetFocus(false)
        m.adRenderer.unobserveFieldScoped("event")
        m.top.removeChild(m.adRenderer)
        m.adRenderer.visible = false
        m.adRenderer = invalid
    end if
end sub