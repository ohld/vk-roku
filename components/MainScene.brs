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
    m.spaces = CreateObject("roRegex", "\s+", "")
    m.rows.observeField("rowItemSelected", "onPick")
    m.rows.observeField("rowItemFocused", "onRowFocus")
    m.skel = m.top.findNode("skel")
    m.sskel = m.top.findNode("sskel")
    m.pulse = m.top.findNode("pulse")
    drawSkel(m.skel, 3)
    drawSkel(m.sskel, 2)
    m.searchG = m.top.findNode("search")
    m.kb = m.top.findNode("kb")
    m.srows = m.top.findNode("srows")
    m.shint = m.top.findNode("shint")
    m.queryLbl = m.top.findNode("query")
    m.searchTimer = m.top.findNode("searchTimer")
    m.srows.observeField("rowItemSelected", "onPick")
    m.recent = m.top.findNode("recent")
    m.recent.observeField("itemSelected", "onRecent")
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
    resetSections()
    loadHistory()   ' ready before the search tab is opened
    openTab(0)
end sub

' 2 rows of placeholder cards with the VideoItem geometry
sub drawSkel(g, cols)
    for i = 0 to cols * 2 - 1
        x = (i mod cols) * 592
        y = Int(i / cols) * 464
        for each r in [[0, 0, 544, 306], [0, 332, 420, 20], [0, 360, 280, 20], [0, 390, 160, 16]]
            b = g.createChild("Rectangle")
            b.translation = [x + r[0], y + r[1]]
            b.width = r[2]
            b.height = r[3]
            b.color = "0x19191AFF"
        end for
    end for
end sub

sub setLoading(g, on)
    g.visible = on
    if m.skel.visible or m.sskel.visible then m.pulse.control = "start" else m.pulse.control = "stop"
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
    resetSections()
    loadHistory()   ' ready before the search tab is opened
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
    setLoading(m.skel, false)
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
    setLoading(m.skel, false)
    if i = 2 and m.q = "" then loadHistory()
    if i < 2 then
        s = m.sec[i]
        if s.root.getChildCount() = 0 then loadMore(i)   ' retry after an error
        showSection(i)
    end if
end sub

function call(method, params, tag)
    t = CreateObject("roSGNode", "ApiTask")
    params.v = "5.199"
    if tag = "search" then params.access_token = m.stoken else params.access_token = m.token
    t.url = m.relay + "https://api.vk.com/method/" + method
    t.params = params
    t.tag = tag
    t.observeField("result", "onResult")
    t.control = "run"
    return t
end function

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

' Both catalog tabs load in parallel from startup. Each section shows its first page (~4-7 videos) at once,
' then keeps paging in the background up to 36 videos, and loads further pages when the user nears the end.
sub resetSections()
    m.sec = []
    for i = 0 to 1
        m.sec.push({root: CreateObject("roSGNode", "ContentNode"), seen: {}, n: 0, nf: "", done: false, task: invalid, err: ""})
        loadMore(i)
    end for
end sub

sub loadMore(i)
    s = m.sec[i]
    if s.task <> invalid or s.done or m.token = "" then return
    p = {section_id: m.sections[i]}
    if s.nf <> "" then p.start_from = s.nf
    s.err = ""
    s.task = call("catalog.getSection", p, "sec" + i.toStr())
end sub

sub onRowFocus()
    if m.tab < 2 and m.rows.content <> invalid and m.rows.rowItemFocused[0] >= m.rows.content.getChildCount() - 2 then loadMore(m.tab)
end sub

sub onSection(i, d)
    s = m.sec[i]
    s.task = invalid
    if d.error <> invalid then
        s.err = "Ошибка ВК: " + d.error.error_msg + chr(10) + "Нажмите OK, чтобы повторить"   ' a later page failed: keep what we have, retry on scroll
    else
        resp = d.response
        if resp = invalid then resp = {}
        vids = playable(resp.videos)
        for each v in vids
            k = v.owner_id.toStr() + "_" + v.id.toStr()
            if not s.seen.doesExist(k) then
                s.seen[k] = true
                addCard(s, v)
            end if
        end for
        s.nf = ""
        if resp.section <> invalid and resp.section.next_from <> invalid then s.nf = resp.section.next_from
        s.done = (s.nf = "")
        if s.n < 36 then loadMore(i)
    end if
    if m.tab = i then showSection(i)
end sub

' grid of 3-card rows, appended in place so focus and scroll survive new pages
sub addCard(s, v)
    if s.n mod 3 = 0 then s.root.createChild("ContentNode")
    s.root.getChild(s.root.getChildCount() - 1).appendChild(card(v))
    s.n = s.n + 1
end sub

sub showSection(i)
    s = m.sec[i]
    if m.token = "" then
        showMessage("Нет входа в ВК")
    else if s.n > 0 then
        m.status.text = ""
        setLoading(m.skel, false)
        if m.rows.content = invalid or not m.rows.content.isSameNode(s.root) then
            m.rows.content = s.root
            m.rows.jumpToRowItem = [0, 0]
        end if
        if m.autoGrid then
            m.autoGrid = false
            m.inTabs = false
            paintTabs()
        end if
        if not m.inTabs then m.rows.setFocus(true)
    else if s.task <> invalid then
        m.rows.content = invalid
        m.status.text = ""
        setLoading(m.skel, true)
    else if s.err <> "" then
        showMessage(s.err)
    else
        showMessage("Здесь пока пусто")
    end if
end sub

sub onResult(e)
    r = e.getData()
    if r.tag = "hist" then
        showHistory(r.data)
        return
    else if r.tag = "histadd" then
        loadHistory()   ' VK has moved the query to the top of its list
        return
    else if r.tag <> "search" then
        i = r.tag.right(1).toInt()
        ' drop pages of a section that was reset (new tokens) meanwhile
        if m.sec[i].task <> invalid and e.getRoSGNode().isSameNode(m.sec[i].task) then onSection(i, r.data)
        return
    end if
    ' only the latest search counts
    if not e.getRoSGNode().isSameNode(m.task) then return
    setLoading(m.sskel, false)
    d = r.data
    if d.error <> invalid then
        m.shint.text = d.error.error_msg
        return
    end if
    vids = []
    if d.response <> invalid then vids = playable(d.response.items)
    m.srows.content = cards(vids, 2)
    m.shint.text = ""
    if vids.count() = 0 then m.shint.text = "Ничего не найдено"
end sub

' rows of perRow cards; each card node carries its VK video object in field "v"
function cards(vids, perRow)
    root = CreateObject("roSGNode", "ContentNode")
    for i = 0 to vids.count() - 1
        if i mod perRow = 0 then row = root.createChild("ContentNode")
        row.appendChild(card(vids[i]))
    end for
    return root
end function

function card(v)
    n = CreateObject("roSGNode", "ContentNode")
    n.HDPosterUrl = thumb(v)
    n.title = clean(v.title)
    n.description = meta(v)
    n.ShortDescriptionLine2 = dur(v.duration)
    n.addFields({v: v})
    return n
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

' smallest unpadded image that covers the 544 px card (VK also sends letterboxed "with_padding" variants)
function thumb(v) as string
    if v.image = invalid then return ""
    best = invalid
    for each im in v.image
        if im.with_padding = invalid and (best = invalid or (best.width < 544 and im.width > best.width) or (im.width >= 544 and im.width < best.width)) then best = im
    end for
    if best = invalid and v.image.count() > 0 then best = v.image[v.image.count() - 1]
    if best = invalid then return ""
    return best.url
end function

' Drop characters the Roku system font has no glyph for (emoji, pictographs, flags, variation selectors,
' zero-width joiners) so titles never show empty boxes; keep Latin, Cyrillic, Greek, general punctuation,
' currency and letterlike symbols (№, ™).
function clean(t) as string
    if t = invalid then return ""
    out = ""
    for i = 1 to Len(t)
        ch = Mid(t, i, 1)
        c = Asc(ch)
        if c >= 32 and c < &h2190 and not (c >= &h200B and c <= &h200F) and not (c >= &h2028 and c <= &h206F and c <> &h2030 and c <> &h2039 and c <> &h203A) then out = out + ch else out = out + " "   ' a dropped emoji often separates two words
    end for
    return m.spaces.ReplaceAll(out, " ").Trim()
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
    ' history list starts under the last key row (RU 6 rows, EN 7) and fills the space down to y=1020
    rows = Int((keys.count() + 5) / 6)
    y = 224 + rows * 70 + 24
    m.top.findNode("recentHdr").translation = [96, y]
    m.recent.translation = [96, y + 40]
    m.recent.numRows = Int((1020 - y - 40 + 4) / 52)
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
        if k = "Ё" then k = "ё" else k = LCase(k)   ' LCase maps Ё (U+0401) to С (U+0421)
        m.q = m.q + k
    end if
    setQuery(m.q)
    m.searchTimer.control = "stop"
    m.searchTimer.control = "start"
end sub

sub setQuery(q)
    m.q = q
    m.queryLbl.text = q
    m.top.findNode("qph").visible = (q = "")
end sub

' VK search history ("Недавние"), read with the official token; VK has no method to delete it
sub loadHistory()
    if m.token <> "" then m.hist = call("catalog.getVideoSearch", {}, "hist")
end sub

sub showHistory(d)
    c = CreateObject("roSGNode", "ContentNode")
    if d.response <> invalid and d.response.suggestions <> invalid then
        for each sg in d.response.suggestions
            if c.getChildCount() < 8 and sg.type = "recent" and sg.title <> invalid then c.createChild("ContentNode").title = clean(sg.title)
        end for
    end if
    has = c.getChildCount() > 0
    if m.recent.hasFocus() and not has then m.kb.setFocus(true)
    m.recent.content = c
    m.recent.visible = has
    m.top.findNode("recentHdr").visible = has
end sub

sub onRecent()
    setQuery(m.recent.content.getChild(m.recent.itemSelected).title)
    m.searchTimer.control = "stop"
    runSearch()
end sub

sub runSearch()
    q = m.q.trim()
    if q = "" then return
    m.shint.text = ""
    m.srows.content = invalid
    setLoading(m.sskel, true)
    m.task = call("video.search", {q: q, count: 60, adult: 0, sort: 2}, "search")
    m.shown = q
end sub

' Search runs live while typing, so the query goes to VK search history only once the user commits to it
' (moves into the results or plays one). The official-token call records it; its results have no files.
sub recordQuery()
    if m.shown = invalid or m.shown = m.recorded then return
    m.recorded = m.shown
    m.histAdd = call("catalog.getVideoSearch", {q: m.shown, need_blocks: 1}, "histadd")
end sub

sub focusKb()
    m.inTabs = false
    paintTabs()
    m.kb.setFocus(true)
end sub

' ---------- playback: 1080p, drop to 720p after 2 real rebuffers; never below 720p (user requirement) ----------
sub onPick(e)
    m.list = e.getRoSGNode()
    if m.list.isSameNode(m.srows) then recordQuery()
    sel = m.list.rowItemSelected
    m.cur = m.list.content.getChild(sel[0]).getChild(sel[1]).v
    viewStart()
    play(firstQuality(), 0)
end sub

'  HLS starts in ~1 segment over one kept-alive connection; progressive mp4 makes Roku open ~6 sequential
'  TLS connections across the ocean (11-14 s). The relay strips HLS variants below 720p and above 1080p.
function firstQuality() as string
    if m.cur.files.hls <> invalid then return "hls"   ' relay answers with the 1080p media playlist (Roku stalls on VK masters)
    if m.cur.files.mp4_1080 <> invalid then return "mp4_1080"
    return "mp4_720"
end function

sub play(k, startAt)
    m.quality = k
    m.failed = false
    m.rebuf = 0
    m.prev = ""
    c = CreateObject("roSGNode", "ContentNode")
    c.url = m.relay + m.cur.files[k]
    if k = "hls" then c.url = m.relay + "h/" + m.cur.files.hls.mid(8)   ' /KEY/h/host/path: relative segment URIs resolve under it
    c.streamFormat = "mp4"
    if k = "hls" then c.streamFormat = "hls"
    c.title = m.cur.title
    c.bookmarkPosition = startAt
    segEnd()
    m.video.control = "stop"
    m.video.content = c
    m.video.visible = true
    m.osd.setFocus(true)   ' keys go to our controls, not the Video node (it eats presses even with enableUI=false)
    m.video.control = "play"
    m.target = -1
    m.top.findNode("osdTitle").text = clean(m.cur.title)
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
    st = m.video.state
    if m.failed or st = "paused" or st = "buffering" or m.target >= 0 then return
    m.osd.visible = false
end sub

sub drawOsd()
    p = m.target
    if p < 0 then p = m.video.position
    d = m.cur.duration   ' VK knows it up front; Video.duration still holds the previous video while loading
    if d = invalid or d = 0 then d = m.video.duration
    w = 0
    if d > 0 then w = Int(1728 * p / d)
    m.top.findNode("osdFill").width = w
    m.top.findNode("osdPos").text = clock(p)
    m.top.findNode("osdDur").text = ""
    if d > 0 then m.top.findNode("osdDur").text = clock(d)
    icon = ""
    if m.video.state = "paused" then icon = "Пауза"
    if m.video.state = "buffering" then icon = "Загрузка…"
    if m.target >= 0 then icon = "Перемотка"
    if m.failed then icon = "Ошибка"
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
        if m.quality = "hls" then
            m.cur.files.delete("hls")
            play(firstQuality(), m.video.position)   ' HLS failed: progressive mp4, still >= 720p
            return
        end if
        if m.quality = "mp4_1080" and m.cur.files.mp4_720 <> invalid then
            play("mp4_720", m.video.position)   ' still >= 720p
            return
        end if
        m.failed = true   ' keep the player open with the reason; Back returns to the list
        m.top.findNode("osdTitle").text = "Не удалось воспроизвести видео"
        showOsd()
    else if st = "finished" and m.prev <> "" then   ' a "finished" right after a fallback restart is the old stream ending
        closeVideo()
    end if
    m.prev = st
    if st = "buffering" or (st = "playing" and m.osd.visible) then showOsd() else if m.osd.visible then drawOsd()   ' re-arm auto-hide once loading ends
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
        else if (key = "OK" or key = "down") and m.rows.content = invalid then
            openTab(m.tab)   ' error / empty: retry
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
        else if key = "down" and m.recent.visible then
            m.recent.setFocus(true)
        else if key = "right" and m.srows.content <> invalid then
            focusResults()
        end if
        return true
    end if
    if m.recent.hasFocus() then
        if key = "up" or key = "back" then
            m.kb.setFocus(true)
        else if key = "right" and m.srows.content <> invalid then
            focusResults()
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

sub focusResults()
    m.srows.setFocus(true)
    recordQuery()
end sub
