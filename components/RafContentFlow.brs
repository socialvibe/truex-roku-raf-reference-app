' Copyright (c) 2019 true[X], Inc. All rights reserved.
'-----------------------------------------------------------------------------------------------------------
' RafContentFlow

sub init()
    ? "TRUE[X] >>> RafContentFlow::init()"
    m.videoPlayer = m.top.findNode("videoPlayer")

    initRafTask()
end sub

'---------------------------------------------------------------------------------------
sub initRafTask()
    ? "TRUE[X] >>> RafContentFlow::initRafTask()"

    if m.rafTask = invalid then
        rafTask = CreateObject("roSGNode", "PlaybackTask")
        rafTask.video = m.videoPlayer
        rafTask.adFacade = m.top.findNode("adFacade")
        rafTask.observeField("playbackEvent", "onPlaybackTaskEvent")

        m.rafTask = rafTask
        rafTask.control = "run"
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    ? "TRUE[X] >>> ContentFlow::onKeyEvent(key=";key;" press=";press.ToStr();")"
    if press and key = "back" and m.adRenderer = invalid then
        ? "TRUE[X] >>> ContentFlow::onKeyEvent() - back pressed while content is playing, requesting stream cancel..."
        ' TODO: Unload player and TrueX via events
        ' m.top.event = { trigger: "cancelStream" }
    end if
    return press
end function

sub onPlaybackTaskEvent(event as object)
    m.top.event = event.getData()
end sub