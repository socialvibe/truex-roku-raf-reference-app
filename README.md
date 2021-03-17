# Overview

This project contains sample source code that demonstrates how to integrate true[X]'s Roku ad renderer in
combination with RAF for client side ads. RAF's responsibilities here are to parse an ad response, detect
if there are any ads to play, and to play any non-truex ads

For a more detailed integration guide, please refer to: https://github.com/socialvibe/truex-roku-integrations.

# Implementation Details

For the purpose of this project, some of the data is hard coded as the primary goal here is to showcase the RAF - TrueX Ad integration for client side handled ads. The core of this implementation starts in `PlaybackTask`. As a brief summary, the app will load and prepare the TrueX Ad Renderer (TAR) component library. Once ready, the app will launch to a simple page (`DetailsFlow`), and waits for the user to start playback by selecting the one/play action. Upon selecting the action, the `RafContentFlow` is started, which sets up some UI elements then invokes `PlaybackTask` where most of the action starts.

In the task, we initialize the player with video metadata and RAF with ads. A very basic use case, wrapped in `vmap-truex.xml` is a mock of a live ad server response with a preroll and midroll adpods with truex ads. A real world practical application will substitute this url with its ad url, and RAF will handle abstracting all the parsing details via `RAF.setAdUrl(url)`. RAF is relatively flexible but it is a black box and assumption here is the ad payload is able to be parsed by RAF. In general as long as the ad payload is a standard format, it will parse correctly. Once RAF has been setup, playback is ready to start.

The core of ad handling is managed by `handleAds()`. This takes care of determining if there is a valid ad to play using `raf.getAds()`. We check for the presence of the `<AdParameter>` tag and the `get.truex.com` domain in the adserver payload to classify an ad if an ad is TrueX or not. `playTrueXAd` will take care of playing a TrueX ad pod rendered on the `adFacade` that was passed from the flow. The TAR event listener `onTruexEvent` will take care of the users interactions, which dictates if the user skips or completes the interaction, and handles if it needs to resume playback or play the other ads. It will also take care of any skip cards that are automatically handled by TAR if conditions are met. If regular ads need to be rendered for any reason (opt out, no truex ads, etc), this is handled by `m.raf.showAds()`. Special callout that RAF takes completely ownership of the thread until the ad is completed or exited that needs to be handled. Since ads are handled by stopping/hiding the content stream, there is a bit of handling to ensure that the stream resumes at the correct location after completing an ad pod.
