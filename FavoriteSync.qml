import QtQuick 2.15

// Keeps the favorites the same on several devices through a WebDAV folder (eg. on a NAS).
//
// Each device writes only its own file, <folder>/<device>.json, with the favorite
// changes made on it: { "<system>/<path under the system>": [favorite 0/1, time in ms] }.
// When the theme starts (and when Pegasus comes back to the front) every device's
// file is read and each game follows its latest change, so removing a favorite
// syncs too and two devices never overwrite each other's file.
// Games are matched by their path below the ROMS_* folder (ROMS_MASTER/snes/x.zip
// and ROMS_FAVORITE/snes/x.zip are the same game), games missing here are skipped.
//
// Needs FavoriteSyncConfig.qml next to this file (not in git, it holds the password):
//     import QtQuick 2.15
//     Item {
//         property string url: "http://nas/dav/folder/"   // ends with a slash
//         property string user: "name"
//         property string password: "secret"
//     }
// Without it the sync stays off.
Item {
    id: root

    readonly property var cfg: cfgLoader.item
    Loader { id: cfgLoader; source: "FavoriteSyncConfig.qml" }

    // Last result, for display: "", "syncing", "ok", "offline"
    property string status: ""

    // Saved in the theme memory: this device's name, its changes and whether
    // they still need uploading
    property string device: ""
    property var own: ({})
    property bool dirty: false
    property bool seeded: false
    property bool busy: false
    property double lastSync: 0

    // Loaded on first use: the main theme may call sync() before this file's
    // Component.onCompleted ran
    property bool loaded: false
    function load() {
        if (loaded)
            return;
        loaded = true;
        const m = api.memory.get('favoriteSync');
        if (m) {
            device = m.device || "";
            own = JSON.parse(JSON.stringify(m.own || {}));
            dirty = !!m.dirty;
            seeded = !!m.seeded;
        }
        if (device === "") {
            device = Qt.platform.os + "-" + Math.random().toString(36).substring(2, 8);
            save();
        }
    }

    function save() {
        api.memory.set('favoriteSync', JSON.parse(JSON.stringify(
            { device: device, own: own, dirty: dirty, seeded: seeded })));
    }

    // "<system>/<path>" of the game's first file, "" if not under a ROMS_* folder
    function keyOf(game) {
        const files = game.files;
        const file = files.get ? files.get(0) : files[0];
        if (!file)
            return "";
        const m = String(file.path).replace(/\\/g, "/").match(/\/ROMS_[A-Z]+\/(.+)$/i);
        return m ? m[1] : "";
    }

    function gamesByKey() {
        const out = {};
        const games = api.allGames;
        for (let i = 0; i < games.count; i++) {
            const game = games.get(i);
            const key = keyOf(game);
            if (key !== "")
                out[key] = game;
        }
        return out;
    }

    // WebDAV request with the configured account (the NAS may use Digest login)
    function request(method, url, body, done) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE)
                done(xhr.status, xhr.responseText);
        };
        xhr.open(method, url, true, cfg.user, cfg.password);
        if (method === "PROPFIND")
            xhr.setRequestHeader("Depth", "1");
        if (body !== null)
            xhr.setRequestHeader("Content-Type", method === "PROPFIND" ? "text/xml" : "application/json");
        xhr.send(body);
    }

    // Called by the details view after the player toggled a favorite
    function record(game) {
        load();
        const key = keyOf(game);
        if (key === "")
            return;
        const changes = own;
        changes[key] = [game.favorite ? 1 : 0, Date.now()];
        own = changes;
        dirty = true;
        save();
        uploadTimer.restart();
    }

    // Several toggles in a row are uploaded together
    Timer {
        id: uploadTimer
        interval: 2000
        onTriggered: root.upload()
    }

    function upload() {
        if (!cfg || !dirty)
            return;
        request("PUT", cfg.url + device + ".json", JSON.stringify(own), function(code) {
            if (code >= 200 && code < 300) {
                dirty = false;
                save();
                status = "ok";
            } else {
                status = "offline";
            }
        });
    }

    function sync() {
        load();
        if (!cfg || busy)
            return;
        busy = true;
        status = "syncing";
        lastSync = Date.now();
        // The NAS answers a body-less PROPFIND from Qt with 400, so ask for a property
        request("PROPFIND", cfg.url, '<?xml version="1.0" encoding="utf-8"?><propfind xmlns="DAV:"><prop><getlastmodified/></prop></propfind>', function(code, text) {
            if (code !== 207) {
                busy = false;
                status = "offline";
                return;
            }
            const names = [];
            const re = /<[^>]*href>([^<]+)<\//g;
            let m;
            while ((m = re.exec(text)) !== null) {
                const name = decodeURIComponent(m[1].replace(/\/$/, "").split("/").pop());
                if (/\.json$/.test(name))
                    names.push(name);
            }
            const files = {};
            let left = names.length;
            if (left === 0)
                merge(files);
            names.forEach(function(name) {
                request("GET", cfg.url + encodeURIComponent(name), null, function(c, t) {
                    if (c === 200) {
                        try { files[name] = JSON.parse(t); } catch (e) {}
                    }
                    if (--left === 0)
                        merge(files);
                });
            });
        });
    }

    function merge(files) {
        const games = gamesByKey();

        // The first sync of a device adds its current favorites (as the oldest
        // change, so any real change on another device wins)
        const changes = own;
        if (!seeded) {
            for (const key in games) {
                if (games[key].favorite && !changes[key])
                    changes[key] = [1, 0];
            }
            seeded = true;
            dirty = true;
        }
        // Our own uploaded file counts too, in case the theme memory was reset
        const mine = files[device + ".json"] || {};
        for (const key in mine) {
            if (!changes[key] || changes[key][1] < mine[key][1])
                changes[key] = mine[key];
        }
        own = changes;

        const latest = {};
        for (const name in files) {
            if (name === device + ".json")
                continue;
            const data = files[name];
            for (const key in data) {
                if (!latest[key] || latest[key][1] < data[key][1])
                    latest[key] = data[key];
            }
        }
        for (const key in own) {
            if (!latest[key] || latest[key][1] <= own[key][1])
                latest[key] = own[key];
        }

        let changed = 0;
        for (const key in latest) {
            const game = games[key];
            const fav = latest[key][0] === 1;
            if (game && game.favorite !== fav) {
                game.favorite = fav;
                changed++;
            }
        }
        console.info("favorite sync:", Object.keys(files).length, "devices,", changed, "changed here");

        busy = false;
        status = "ok";
        save();
        upload();
    }

    // Pegasus stays open while a game runs; sync again when it comes back
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive && Date.now() - root.lastSync > 30000)
                root.sync();
        }
    }
}
