#!/usr/bin/env python3
"""Get both VK tokens and push them to the TV.
  python3 login.py <TV IP>
1. Official VK Android token (For you / Trending) via QR login: open the printed link on a phone
   logged into VK and confirm; if VK asks, type the code it sends.
2. Kate Mobile token (search with playable files): open the printed link, log in, paste the final URL.
Tokens go to the TV's registry via ECP (`launch/dev?token=&stoken=`) and are never written to disk.
The dev channel must already be installed (./deploy.sh install); a re-install wipes the registry."""
import json, sys, time, urllib.parse, urllib.request

C, SECRET = "2274003", "hHbZxrka2uZ6jB1inYsH"   # public credentials of the VK Android app
KATE = "https://oauth.vk.com/authorize?client_id=2685278&scope=video,offline&redirect_uri=https://oauth.vk.com/blank.html&display=page&response_type=token&revoke=1"


def get(url, **p):
    return json.load(urllib.request.urlopen(url + "?" + urllib.parse.urlencode(p), timeout=20))


def api(method, **p):
    return get("https://api.vk.com/method/" + method, v="5.199", **p)


def official():
    anon = get("https://oauth.vk.com/get_anonym_token", client_id=C, client_secret=SECRET, v="5.199")["token"]
    r = api("auth.getAuthCode", client_id=C, device_name="Roku TV", access_token=anon)["response"]
    print("1) Откройте на телефоне и подтвердите вход:\n  ", r["auth_url"])
    asked = False
    for _ in range(300):
        time.sleep(2)
        d = api("auth.checkAuthCode", auth_hash=r["auth_hash"], client_id=C, access_token=anon).get("response", {})
        if d.get("access_token"):
            return d["access_token"]
        if d.get("status") == 5 and not asked:   # VK wants a confirmation code
            asked = True
            code = input("   Код подтверждения от ВК: ").strip()
            print("  ", api("auth.validateAuthCode", access_token=anon, auth_hash=r["auth_hash"], validation_code=code))
    sys.exit("QR-вход не подтверждён")


def kate():
    print("2) Откройте, войдите и вставьте адрес страницы, на которую попадёте:\n  ", KATE)
    frag = urllib.parse.parse_qs(input("   URL: ").strip().split("#", 1)[-1])
    return frag["access_token"][0]


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    q = urllib.parse.urlencode({"token": official(), "stoken": kate()})
    urllib.request.urlopen(urllib.request.Request(f"http://{sys.argv[1]}:8060/launch/dev?{q}", method="POST"), timeout=10)
    print("Готово: токены отправлены, приложение запущено на телевизоре.")
