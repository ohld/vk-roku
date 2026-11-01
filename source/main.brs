' Launch params (once, via ECP): token=<official VK token>, stoken=<Kate token>; both are saved in the registry.
sub Main(args as Dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.setMessagePort(port)
    scene = screen.CreateScene("MainScene")
    screen.show()
    if args.token <> invalid or args.stoken <> invalid then scene.tokens = {token: args.token, stoken: args.stoken}
    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent" and msg.isScreenClosed() then return
    end while
end sub
