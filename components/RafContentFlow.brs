' Copyright (c) 2019 true[X], Inc. All rights reserved.
'-----------------------------------------------------------------------------------------------------------
' RafContentFlow
' -----------------------------------------------------------------------------------------------------------
' Flow that sets up any necessary UX elements such as the player and ad components
' And starts the task that will begin the playback experience
'-----------------------------------------------------------------------------------------------------------
sub init()
    ? "TRUE[X] >>> RafContentFlow::init()"
    m.videoPlayer = m.top.findNode("videoPlayer")

    initRafTask()
end sub

'-------------------------------------------
' Sets up the task responsible for managing the player, RAF, and TrueX
'-------------------------------------------
sub initRafTask()
    ? "TRUE[X] >>> RafContentFlow::initRafTask()"

    if m.rafTask = invalid then
        rafTask = CreateObject("roSGNode", "PlaybackTask")
        rafTask.video = m.videoPlayer
        rafTask.adFacade = m.top.findNode("adFacade")
        rafTask.observeField("playerDisposed", "onPlaybackTaskEvent")

        m.rafTask = rafTask
        rafTask.control = "run"
    end if
end sub

'-------------------------------------------
' Listens to key events that bubble up to the flow
' Currently only handles back actions, to initiate the exit process
'-------------------------------------------
function onKeyEvent(key as string, press as boolean) as boolean
    ? "TRUE[X] >>> ContentFlow::onKeyEvent(key=";key;" press=";press.ToStr();")"
    if press and key = "back" then
        ? "TRUE[X] >>> ContentFlow::onKeyEvent() - back pressed while content is playing, requesting stream cancel..."
        m.rafTask.exitPlayback = true
    end if
    return press
end function

'-------------------------------------------
' Listener to know when the task thread has finished any clean up
' parameter:
'   * event as associative array - Event object from the task
'-------------------------------------------
sub onPlaybackTaskEvent(event as object)
    name = event.getField()
    if name = "playerDisposed" then
        m.top.event = { trigger: "cancelStream" }
    end if
end sub