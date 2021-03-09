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

sub onPlaybackTaskEvent(event as object)
    m.top.event = event.getData()
end sub