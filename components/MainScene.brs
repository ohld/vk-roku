' VK Видео for Roku. Layout follows the official VK Video Android TV app: dark #0A0A0A, 16:9 cards.
' All VK API and video traffic goes through our relay (relay.py on Hetzner, URL baked in by deploy.sh):
' Brazil -> RU VK CDN direct is ~2 Mbit/s, and VK video URLs are bound to the IP that called the API.
sub init()
    m.reg = CreateObject("roRegistrySection", "vk")
    m.token = m.reg.Read("token")      ' official VK Android token: catalog For you / Trending
    m.stoken = m.reg.Read("stoken")    ' Kate Mobile token: video.search returns playable files
    m.relay = relayDefault()
    m.sections = ["PUldVA8AR0RzSVNUQUYOCCIYS1oXDUlcdxY", "PUldVA8AR0RzSVNURVsbEyoKGylBRg4IIhhLWhcNSVx3Fg"]
    m.rows = m.top.findNode("rows")
    m.status = m.top.findNode("status")
    m.video = m.top.findNode("video")
    m.underline = m.top.findNode("underline")
    m.tabLabels = m.top.findNode("tabs").getChildren(-1, 0)
    m.cache = {}
    m.rows.observeField("rowItemSelected", "onPick")
    m.video.observeField("state", "onVideoState")
    m.tab = 0
    m.inTabs = false
    openTab(0)
end sub

sub onTokens()
    t = m.top.tokens
    if t.token <> invalid then
        m.token = t.token
        m.reg.Write("token", t.token)
    end if
    if t.stoken <> invalid then
        m.stoken = t.stoken
        m.reg.Write("stoken", t.stoken)
    end if
    m.reg.Flush()
    m.cache = {}
    openTab(0)
end sub

sub paintTabs()
    for i = 0 to m.tabLabels.count() - 1
        c = "0x6F7378FF"
        if i = m.tab then
            c = "0xE1E3E6FF"
            if m.inTabs then c = "0xFFFFFFFF"
        end if
        m.tabLabels[i].color = c
    end for
    l = m.tabLabels[m.tab]
    m.underline.translation = [96 + l.translation[0], 100]
    m.underline.width = l.boundingRect().width
    if m.inTabs then m.underline.color = "0x0077FFFF" else m.underline.color = "0x0077FF80"
end sub

' focus the tab bar (also the safe landing spot after errors / empty results)
sub toTabs()
    m.inTabs = true
    paintTabs()
    m.top.setFocus(true)
end sub

' message instead of the grid; focus goes to tabs so the remote never dead-ends
sub showMessage(t)
    m.rows.content = invalid
    m.status.text = t
    toTabs()
end sub

sub openTab(i)
    m.tab = i
    paintTabs()
    if i = 2 then
        askSearch()
    else if m.cache.doesExist(i.toStr()) then
        showGrid(m.cache[i.toStr()], "")
    else
        loadSection(i)
    end if
end sub

sub call(method, params, tag)
    t = CreateObject("roSGNode", "ApiTask")
    params.v = "5.199"
    if tag = "search" then params.access_token = m.stoken else params.access_token = m.token
    t.url = m.relay + "https://api.vk.com/method/" + method
    t.params = params
    t.tag = tag
    t.observeField("result", "onResult")
    m.task = t
    t.control = "run"
end sub

sub loadSection(i)
    if m.token = "" then
        showMessage("Нет входа в ВК")
        return
    end if
    m.rows.content = invalid
    m.status.text = "Загрузка…"
    m.secIdx = i
    m.acc = []
    m.seen = {}
    call("catalog.getSection", {section_id: m.sections[i]}, "sec")
end sub

sub onResult(e)
    ' only the latest request counts: results of a request superseded by a tab switch / new search are dropped
    if not e.getRoSGNode().isSameNode(m.task) then return
    r = e.getData()
    d = r.data
    if d.error <> invalid then
        showMessage("Ошибка ВК: " + d.error.error_msg)
        return
    end if
    resp = d.response
    if resp = invalid then resp = {}
    if r.tag = "sec" then
        vids = resp.videos
        if vids = invalid then vids = []
        for each v in vids
            k = v.owner_id.toStr() + "_" + v.id.toStr()
            if not m.seen.doesExist(k) then
                m.seen[k] = true
                m.acc.push(v)
            end if
        end for
        nf = invalid
        if resp.section <> invalid then nf = resp.section.next_from
        ' VK returns ~5 videos per page; fetch pages until 36
        if nf <> invalid and nf <> "" and m.acc.count() < 36 then
            call("catalog.getSection", {section_id: m.sections[m.secIdx], start_from: nf}, "sec")
        else
            vids = playable(m.acc)
            m.cache[m.secIdx.toStr()] = vids
            showGrid(vids, "Здесь пока пусто")
        end if
    else
        showGrid(playable(resp.items), "Ничего не найдено: " + m.query)
    end if
end sub

' 3 cards per row, 2 rows visible; each card node carries its VK video object in field "v"
sub showGrid(vids, emptyMsg)
    if vids.count() = 0 then
        showMessage(emptyMsg)
        return
    end if
    m.status.text = ""
    root = CreateObject("roSGNode", "ContentNode")
    for i = 0 to vids.count() - 1
        if i mod 3 = 0 then row = root.createChild("ContentNode")
        v = vids[i]
        n = row.createChild("ContentNode")
        n.HDPosterUrl = thumb(v)
        n.title = v.title
        n.description = meta(v)
        n.ShortDescriptionLine2 = dur(v.duration)
        n.addFields({v: v})
    end for
    m.rows.content = root
    m.rows.jumpToRowItem = [0, 0]
    if not m.inTabs then m.rows.setFocus(true)
end sub

function playable(vids)
    out = []
    if vids = invalid then return out
    for each v in vids
        if v <> invalid and v.files <> invalid and (v.files.mp4_1080 <> invalid or v.files.mp4_720 <> invalid) then out.push(v)
    end for
    return out
end function

' ---------- formatting ----------
function dur(sec) as string
    if sec = invalid or sec = 0 then return ""
    h = Int(sec / 3600)
    mi = Int((sec mod 3600) / 60)
    se = sec mod 60
    ss = se.toStr()
    if se < 10 then ss = "0" + ss
    if h > 0 then
        ms = mi.toStr()
        if mi < 10 then ms = "0" + ms
        return h.toStr() + ":" + ms + ":" + ss
    end if
    return mi.toStr() + ":" + ss
end function

function meta(v) as string
    n = v.views
    if n = invalid then return ""
    if n >= 1000000 then
        t = (Int(n / 100000) / 10).toStr() + " млн"
    else if n >= 1000 then
        t = Int(n / 1000).toStr() + " тыс."
    else
        t = n.toStr()
    end if
    return t + " просмотров"
end function

function thumb(v) as string
    if v.image <> invalid and v.image.count() > 0 then
        best = v.image[0]
        for each im in v.image
            if im.width <= 1280 and im.width > best.width then best = im
        end for
        return best.url
    end if
    return ""
end function

' ---------- search ----------
sub askSearch()
    d = CreateObject("roSGNode", "StandardKeyboardDialog")
    d.title = "Поиск видео ВК"
    d.buttons = ["Найти", "Отмена"]
    d.observeField("buttonSelected", "onSearchDialog")
    m.top.dialog = d
end sub

sub onSearchDialog()
    d = m.top.dialog
    txt = d.text
    ok = d.buttonSelected = 0
    d.close = true
    if not ok or txt = "" then
        toTabs()
        return
    end if
    m.query = txt
    m.rows.content = invalid
    m.inTabs = false
    paintTabs()
    m.status.text = "Поиск: " + txt + "…"
    call("video.search", {q: txt, count: 120, adult: 0, sort: 2}, "search")
end sub

' ---------- playback: 1080p, drop to 720p after 2 real rebuffers; never below 720p (user requirement) ----------
sub onPick()
    sel = m.rows.rowItemSelected
    m.cur = m.rows.content.getChild(sel[0]).getChild(sel[1]).v
    k = "mp4_720"
    if m.cur.files.mp4_1080 <> invalid then k = "mp4_1080"
    play(k, 0)
end sub

sub play(k, startAt)
    m.quality = k
    m.rebuf = 0
    m.prev = ""
    c = CreateObject("roSGNode", "ContentNode")
    c.url = m.relay + m.cur.files[k]
    c.streamFormat = "mp4"
    c.title = m.cur.title
    c.bookmarkPosition = startAt
    m.video.control = "stop"
    m.video.content = c
    m.video.visible = true
    m.video.setFocus(true)
    m.video.control = "play"
end sub

sub onVideoState()
    st = m.video.state
    ' count only stalls during playback; trickplay goes paused -> buffering and must not downgrade quality
    if st = "buffering" and m.prev = "playing" then
        m.rebuf = m.rebuf + 1
        if m.rebuf >= 2 and m.quality = "mp4_1080" and m.cur.files.mp4_720 <> invalid then
            play("mp4_720", m.video.position)
            return
        end if
    else if st = "error" then
        closeVideo()
        m.status.text = "Ошибка воспроизведения: " + m.video.errorMsg
    else if st = "finished" then
        closeVideo()
    end if
    m.prev = st
end sub

sub closeVideo()
    m.video.control = "stop"
    m.video.visible = false
    if m.rows.content <> invalid then m.rows.setFocus(true) else toTabs()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.video.visible then
        if key = "back" then
            closeVideo()
            return true
        end if
        return false
    end if
    if m.inTabs then
        if key = "back" then return false   ' let Back exit the app from the tab bar
        if key = "left" and m.tab > 0 then
            openTab(m.tab - 1)
        else if key = "right" and m.tab < 2 then
            openTab(m.tab + 1)
        else if key = "OK" and m.tab = 2 then
            askSearch()
        else if key = "down" and m.rows.content <> invalid then
            m.inTabs = false
            paintTabs()
            m.rows.setFocus(true)
        end if
        return true
    end if
    if m.rows.hasFocus() and (key = "back" or (key = "up" and m.rows.rowItemFocused[0] = 0)) then
        toTabs()
        return true
    end if
    return false
end function
