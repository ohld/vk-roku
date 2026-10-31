sub Main(args as Dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.setMessagePort(port)
    scene = screen.CreateScene("MainScene")
    screen.show()
    input = CreateObject("roInput")
    input.setMessagePort(port)
    handleArgs(scene, args)
    while true
        msg = wait(0, port)
        t = type(msg)
        if t = "roSGScreenEvent" and msg.isScreenClosed() then return
        if t = "roInputEvent" and msg.isInput() then handleArgs(scene, msg.getInfo())
    end while
end sub

sub handleArgs(scene, a)
    if a = invalid then return
    if a.token <> invalid and a.token <> "" then scene.externalToken = a.token
    if a.relay <> invalid then scene.externalToken = "r:" + a.relay
    if a.q <> invalid and a.q <> "" then scene.externalSearch = a.q
end sub
