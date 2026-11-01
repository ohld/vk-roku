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
    m.searchG = m.top.findNode("search")
    m.kb = m.top.findNode("kb")
    m.srows = m.top.findNode("srows")
    m.shint = m.top.findNode("shint")
    m.queryLbl = m.top.findNode("query")
    m.searchTimer = m.top.findNode("searchTimer")
    m.srows.observeField("rowItemSelected", "onPick")
    m.kb.observeField("itemSelected", "onKey")
    m.searchTimer.observeField("fire", "runSearch")
    m.q = ""
    m.lang = "ru"
    fillKb()
    m.list = m.rows
    m.video.observeField("state", "onVideoState")
    m.video.observeField("position", "onPos")
    m.osd = m.top.findNode("osd")
    m.osdTimer = m.top.findNode("osdTimer")
    m.seekTimer = m.top.findNode("seekTimer")
    m.holdTimer = m.top.findNode("holdTimer")
    m.osdTimer.observeField("fire", "hideOsd")
    m.seekTimer.observeField("fire", "commitSeek")
    m.holdTimer.observeField("fire", "onHold")
    m.target = -1
    m.holdDir = 0
    m.tab = 0
    toTabs()            ' keys work while the first page loads
    m.autoGrid = true   ' ...then focus drops into the grid unless the user already moved
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
    m.top.findNode("tabs").setFocus(true)   ' Scene.setFocus leaves focus on the child
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
    m.searchG.visible = (i = 2)
    m.rows.visible = (i <> 2)
    m.status.visible = (i <> 2)
    if i = 2 then
        m.task = invalid   ' drop late section pages
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

' VK calls whose answer we don't need (view telemetry)
sub fire(method, params)
    t = CreateObject("roSGNode", "ApiTask")
    params.v = "5.199"
    params.access_token = m.token
    t.url = m.relay + "https://api.vk.com/method/" + method
    t.params = params
    t.control = "run"
    if m.bg = invalid or m.bg.count() > 8 then m.bg = []
    m.bg.push(t)   ' keep references while they run
end sub

' what the official app sends: history record on start, watched ranges on exit
sub viewStart()
    m.ranges = []
    m.segStart = -1
    m.started = CreateObject("roDateTime").AsSeconds()
    fire("video.addViewingHistoryRecord", {video_id: m.cur.owner_id.toStr() + "_" + m.cur.id.toStr()})
end sub

sub segEnd()
    if m.segStart < 0 then return
    e = Int(m.video.position)
    if e > m.segStart then m.ranges.push(m.segStart.toStr() + "-" + e.toStr())
    m.segStart = -1
end sub

sub viewEnd()
    segEnd()
    if m.ranges = invalid or m.ranges.count() = 0 then return
    p = {owner_id: m.cur.owner_id, video_id: m.cur.id, ranges: m.ranges.join(","), start_time: m.started, state_start: "fullscreen", state_end: "fullscreen", end_stream_reason: "session_end", autoplay: 0}
    if m.cur.track_code <> invalid then p.track_code = m.cur.track_code
    fire("video.viewSegments", p)
    m.ranges = []
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
    if d.error <> invalid and r.tag = "sec" and m.acc.count() > 0 then
        d = {response: {}}   ' a later page failed: show what we have
    end if
    if d.error <> invalid then
        if r.tag = "search" then
            m.shint.text = d.error.error_msg
            return
        end if
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
        vids = playable(resp.items)
        m.srows.content = cards(vids, 2)
        m.shint.text = ""
        if vids.count() = 0 then m.shint.text = "Ничего не найдено"
    end if
end sub

' 3 cards per row, 2 rows visible; each card node carries its VK video object in field "v"
sub showGrid(vids, emptyMsg)
    if vids.count() = 0 then
        showMessage(emptyMsg)
        return
    end if
    m.status.text = ""
    m.rows.content = cards(vids, 3)
    m.rows.jumpToRowItem = [0, 0]
    if m.autoGrid then
        m.autoGrid = false
        m.inTabs = false
        paintTabs()
    end if
    if not m.inTabs then m.rows.setFocus(true)
end sub

' rows of perRow cards; each card node carries its VK video object in field "v"
function cards(vids, perRow)
    root = CreateObject("roSGNode", "ContentNode")
    for i = 0 to vids.count() - 1
        if i mod perRow = 0 then row = root.createChild("ContentNode")
        v = vids[i]
        n = row.createChild("ContentNode")
        n.HDPosterUrl = thumb(v)
        n.title = v.title
        n.description = meta(v)
        n.ShortDescriptionLine2 = dur(v.duration)
        n.addFields({v: v})
    end for
    return root
end function

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
' Roku keyboards have no Cyrillic, so the search tab has its own grid keyboard; results refresh 0.8 s after typing
sub fillKb()
    keys = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ".split("")
    if m.lang = "en" then keys = "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890".split("")
    keys.append(["Пробел", "Стереть", "ABC"])
    if m.lang = "en" then keys[keys.count() - 1] = "АБВ"
    c = CreateObject("roSGNode", "ContentNode")
    for each k in keys
        c.createChild("ContentNode").title = k
    end for
    m.kb.content = c
end sub

sub onKey()
    k = m.kb.content.getChild(m.kb.itemSelected).title
    if k = "ABC" or k = "АБВ" then
        if m.lang = "ru" then m.lang = "en" else m.lang = "ru"
        fillKb()
        m.kb.jumpToItem = m.kb.content.getChildCount() - 1
        return
    else if k = "Стереть" then
        if m.q.len() > 0 then m.q = m.q.left(m.q.len() - 1)
    else if k = "Пробел" then
        m.q = m.q + " "
    else
        m.q = m.q + LCase(k)
    end if
    m.queryLbl.text = m.q
    m.searchTimer.control = "stop"
    m.searchTimer.control = "start"
end sub

sub runSearch()
    q = m.q.trim()
    if q = "" then return
    m.shint.text = "Поиск…"
    m.srows.content = invalid
    call("video.search", {q: q, count: 60, adult: 0, sort: 2}, "search")
end sub

sub focusKb()
    m.inTabs = false
    paintTabs()
    m.kb.setFocus(true)
end sub

' ---------- playback: 1080p, drop to 720p after 2 real rebuffers; never below 720p (user requirement) ----------
sub onPick(e)
    m.list = e.getRoSGNode()
    sel = m.list.rowItemSelected
    m.cur = m.list.content.getChild(sel[0]).getChild(sel[1]).v
    k = "mp4_720"
    if m.cur.files.mp4_1080 <> invalid then k = "mp4_1080"
    viewStart()
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
    segEnd()
    m.video.control = "stop"
    m.video.content = c
    m.video.visible = true
    m.osd.setFocus(true)   ' keys go to our controls, not the Video node (it eats presses even with enableUI=false)
    m.video.control = "play"
    m.target = -1
    m.top.findNode("osdTitle").text = m.cur.title
    showOsd()
end sub

' Own player controls (native trickplay UI is off): OK = pause/resume at once,
' left/right = seek 10 s at once, hold = accelerating scrub; loading starts 0.6 s after the last press, no OK needed.
sub showOsd()
    m.osd.visible = true
    drawOsd()
    m.osdTimer.control = "stop"
    m.osdTimer.control = "start"
end sub

sub hideOsd()
    if m.video.state = "paused" or m.target >= 0 then return
    m.osd.visible = false
end sub

sub drawOsd()
    p = m.target
    if p < 0 then p = m.video.position
    d = m.video.duration
    w = 0
    if d > 0 then w = Int(1728 * p / d)
    m.top.findNode("osdFill").width = w
    m.top.findNode("osdPos").text = clock(p)
    m.top.findNode("osdDur").text = clock(d)
    icon = ""
    if m.video.state = "paused" then icon = "Пауза"
    if m.video.state = "buffering" then icon = "Загрузка…"
    m.top.findNode("osdIcon").text = icon
end sub

function clock(sec) as string
    t = dur(Int(sec))
    if t = "" then t = "0:00"
    return t
end function

sub onPos()
    if m.osd.visible and m.target < 0 then drawOsd()
end sub

sub nudge(d)
    if m.target < 0 then m.target = m.video.position
    m.target = m.target + d
    if m.target < 0 then m.target = 0
    if m.video.duration > 0 and m.target > m.video.duration - 5 then m.target = m.video.duration - 5
    m.seekTimer.control = "stop"
    showOsd()
end sub

sub onHold()
    m.holdN = m.holdN + 1
    stepSec = 10 * (1 + Int(m.holdN / 2))
    if stepSec > 120 then stepSec = 120
    nudge(m.holdDir * stepSec)
end sub

sub commitSeek()
    if m.target < 0 then return
    segEnd()   ' close the watched range before position jumps
    m.prev = ""   ' a seek's buffering is not a stall
    m.video.seek = m.target
    m.target = -1
    showOsd()
end sub

function playerKey(key, press) as boolean
    dir = 0
    if key = "right" or key = "fastforward" then dir = 1
    if key = "left" or key = "rewind" then dir = -1
    if not press then
        if dir <> 0 then
            m.holdTimer.control = "stop"
            m.holdDir = 0
            m.seekTimer.control = "start"
        end if
        return dir <> 0
    end if
    if key = "back" then
        closeVideo()
    else if key = "OK" or key = "play" then
        if m.video.state = "paused" then m.video.control = "resume" else m.video.control = "pause"
        showOsd()
    else if dir <> 0 then
        if m.holdDir = dir then return true   ' key auto-repeat while held
        m.holdDir = dir
        m.holdN = 0
        nudge(dir * 10)
        m.holdTimer.control = "start"
    else
        showOsd()
    end if
    return true
end function

sub onVideoState()
    st = m.video.state
    if st = "playing" then
        if m.segStart < 0 then m.segStart = Int(m.video.position)
    else
        segEnd()
    end if
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
    if m.osd.visible then drawOsd()
end sub

sub closeVideo()
    viewEnd()
    m.video.control = "stop"
    m.video.visible = false
    m.osd.visible = false
    m.holdTimer.control = "stop"
    m.seekTimer.control = "stop"
    m.target = -1
    if m.list.content <> invalid then m.list.setFocus(true) else toTabs()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if m.video.visible then return playerKey(key, press)
    if not press then return false
    if m.inTabs then
        m.autoGrid = false
        if key = "back" then return false   ' let Back exit the app from the tab bar
        if key = "left" and m.tab > 0 then
            openTab(m.tab - 1)
        else if key = "right" and m.tab < 2 then
            openTab(m.tab + 1)
        else if (key = "OK" or key = "down") and m.tab = 2 then
            focusKb()
        else if key = "down" and m.rows.content <> invalid then
            m.inTabs = false
            paintTabs()
            m.rows.setFocus(true)
        end if
        return true
    end if
    if m.kb.hasFocus() then
        if key = "up" or key = "back" then
            toTabs()
        else if key = "right" and m.srows.content <> invalid then
            m.srows.setFocus(true)
        end if
        return true
    end if
    if m.srows.hasFocus() then
        if key = "left" or key = "back" then
            m.kb.setFocus(true)
        else if key = "up" then
            toTabs()
        end if
        return true
    end if
    if m.rows.hasFocus() and (key = "back" or key = "up")   ' up reaches us only when the RowList is already on its top row then
        toTabs()
        return true
    end if
    return false
end function
