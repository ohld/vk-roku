' VK Видео for Roku. Layout follows the official VK Video Android TV app: dark #0A0A0A, horizontal shelves, 16:9 cards.
sub init()
    m.reg = CreateObject("roRegistrySection", "vk")
    m.token = m.reg.Read("token")      ' official VK Android token (QR login): catalog For you / Trending
    m.stoken = m.reg.Read("stoken")    ' Kate Mobile token: video.search returns playable files
    ' VK traffic goes through our relay (relay.py on Hetzner): Brazil -> RU VK CDN direct is ~2 Mbit/s.
    ' Registry override from `relay=` launch param; "-" = direct.
    m.relay = m.reg.Read("relay")
    if m.relay = "" then m.relay = relayDefault()
    if m.relay = "-" then m.relay = ""
    m.sections = [{title: "Для вас", id: "PUldVA8AR0RzSVNUQUYOCCIYS1oXDUlcdxY"}, {title: "Тренды", id: "PUldVA8AR0RzSVNURVsbEyoKGylBRg4IIhhLWhcNSVx3Fg"}]
    m.rows = m.top.findNode("rows")
    m.status = m.top.findNode("status")
    m.video = m.top.findNode("video")
    m.underline = m.top.findNode("underline")
    m.cache = {}
    m.tabLabels = []
    x = 0
    for each t in ["Для вас", "Тренды", "Поиск"]
        l = CreateObject("roSGNode", "Label")
        l.text = t
        l.font = font(30)
        l.translation = [x, 0]
        m.top.findNode("tabs").appendChild(l)
        m.tabLabels.push(l)
        x = x + l.boundingRect().width + 56
    end for
    m.rows.observeField("rowItemSelected", "onPick")
    m.video.observeField("state", "onVideoState")
    m.tab = 0
    m.inTabs = false
    paintTabs()
    openTab(0)
end sub

sub paintTabs()
    for i = 0 to m.tabLabels.count() - 1
        l = m.tabLabels[i]
        if i = m.tab then
            if m.inTabs then l.color = "0xFFFFFFFF" else l.color = "0xE1E3E6FF"
        else
            l.color = "0x6F7378FF"
        end if
    end for
    r = m.tabLabels[m.tab].boundingRect()
    m.underline.translation = [96 + m.tabLabels[m.tab].translation[0], 100]
    m.underline.width = r.width
    if m.inTabs then m.underline.color = "0x0077FFFF" else m.underline.color = "0x0077FF80"
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

function font(size)
    f = CreateObject("roSGNode", "Font")
    f.uri = "font:SystemFontFile"
    f.size = size
    return f
end function

sub setStatus(t)
    m.status.text = t
end sub

sub onExternalToken()
    t = m.top.externalToken
    if t.left(2) = "r:" then
        ' "r:" + relay base, "r:-" = direct, "r:" = back to the built-in relay
        m.reg.Write("relay", t.mid(2))
        m.relay = t.mid(2)
        if m.relay = "" then m.relay = relayDefault()
        if m.relay = "-" then m.relay = ""
        m.cache = {}
        openTab(m.tab)
    else if t.left(2) = "s:" then
        m.stoken = t.mid(2)
        m.reg.Write("stoken", m.stoken)
    else
        m.token = t
        m.reg.Write("token", m.token)
        m.cache = {}
        openTab(0)
    end if
    m.reg.Flush()
end sub

sub call(method, params, tag)
    t = CreateObject("roSGNode", "ApiTask")
    params.v = "5.199"
    if tag = "search" then params.access_token = m.stoken else params.access_token = m.token
    t.url = m.relay + "https://api.vk.com/method/" + method
    t.params = params
    t.tag = tag
    t.observeField("result", "onResult")
    t.control = "run"
    m.task = t
end sub

sub loadSection(i)
    if m.token = "" then
        setStatus("Нет входа в ВК")
        return
    end if
    m.rows.content = invalid
    setStatus("Загрузка…")
    m.secIdx = i
    m.acc = []
    m.seen = {}
    call("catalog.getSection", {section_id: m.sections[i].id}, "sec")
end sub

sub onResult(e)
    r = e.getData()
    d = r.data
    if d.error <> invalid then
        setStatus("Ошибка ВК: " + d.error.error_msg)
        return
    end if
    if r.tag = "sec" then
        if m.secIdx <> m.tab then return
        for each v in d.response.videos
            k = v.owner_id.toStr() + "_" + v.id.toStr()
            if not m.seen.doesExist(k) then
                m.seen[k] = true
                m.acc.push(v)
            end if
        end for
        nf = d.response.section.next_from
        ' VK returns ~5 videos per page; fetch pages until 36
        if nf <> invalid and nf <> "" and m.acc.count() < 36 then
            call("catalog.getSection", {section_id: m.sections[m.secIdx].id, start_from: nf}, "sec")
        else
            vids = playable(m.acc)
            m.cache[m.secIdx.toStr()] = vids
            showGrid(vids, "")
        end if
    else
        showGrid(playable(d.response.items), "Ничего не найдено: " + m.query)
    end if
end sub

' 3 cards per row, 2 rows visible
sub showGrid(vids, emptyMsg)
    if vids.count() = 0 then
        m.rows.content = invalid
        setStatus(emptyMsg)
        return
    end if
    setStatus("")
    m.data = []
    root = CreateObject("roSGNode", "ContentNode")
    i = 0
    while i < vids.count()
        row = root.createChild("ContentNode")
        chunk = []
        j = i
        while j < vids.count() and j < i + 3
            v = vids[j]
            chunk.push(v)
            n = row.createChild("ContentNode")
            n.HDPosterUrl = thumb(v)
            n.title = v.title
            n.description = meta(v)
            n.ShortDescriptionLine2 = dur(v.duration)
            j = j + 1
        end while
        m.data.push(chunk)
        i = i + 3
    end while
    m.rows.content = root
    m.rows.jumpToRowItem = [0, 0]
    if not m.inTabs then m.rows.setFocus(true)
end sub

function playable(vids)
    out = []
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
    if not ok or txt = "" then return
    doSearch(txt)
end sub

sub onExternalSearch()
    m.tab = 2
    m.inTabs = false
    paintTabs()
    doSearch(m.top.externalSearch)
end sub

sub doSearch(txt)
    m.query = txt
    m.rows.content = invalid
    m.inTabs = false
    paintTabs()
    setStatus("Поиск: " + txt + "…")
    call("video.search", {q: txt, count: 120, adult: 0, sort: 2}, "search")
end sub

' ---------- playback: 1080p, drop to 720p after 2 rebuffers; never below 720p ----------
sub onPick()
    sel = m.rows.rowItemSelected
    m.cur = m.data[sel[0]][sel[1]]
    playQuality(["mp4_1080", "mp4_720"], 0)
end sub

sub playQuality(keys, startAt)
    f = m.cur.files
    url = ""
    for each k in keys
        if url = "" and f[k] <> invalid then
            url = f[k]
            m.quality = k
        end if
    end for
    if url = "" then return
    m.rebuf = 0
    m.played = false
    c = CreateObject("roSGNode", "ContentNode")
    c.url = m.relay + url
    c.streamFormat = "mp4"
    c.title = m.cur.title
    c.HttpHeaders = ["User-Agent: VKAndroidApp/8.120-21460 (Android 13; SDK 33; arm64-v8a; Google Pixel; ru; 2400x1080)"]
    m.video.content = c
    m.video.visible = true
    m.video.setFocus(true)
    m.video.control = "play"
    if startAt > 0 then m.video.seek = startAt
end sub

sub onVideoState()
    st = m.video.state
    if st = "playing" then
        m.played = true
    else if st = "buffering" and m.played then
        m.rebuf = m.rebuf + 1
        if m.rebuf >= 2 and m.quality = "mp4_1080" and m.cur.files.mp4_720 <> invalid then
            playQuality(["mp4_720"], m.video.position)
        end if
    else if st = "error" then
        setStatus("Ошибка воспроизведения: " + m.video.errorMsg)
        closeVideo()
    else if st = "finished" then
        closeVideo()
    end if
end sub

sub closeVideo()
    m.video.control = "stop"
    m.video.visible = false
    m.rows.setFocus(true)
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
    if (key = "up" or key = "back") and m.rows.hasFocus() then
        if key = "back" or m.rows.rowItemFocused[0] = 0 then
            m.inTabs = true
            paintTabs()
            m.top.setFocus(true)
            return true
        end if
    end if
    return false
end function
