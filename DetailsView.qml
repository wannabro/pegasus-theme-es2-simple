import QtQuick 2.15 // Text padding needs 2.7, horizontal Gradient needs 2.13
import QtMultimedia 5.9
import QtGraphicalEffects 1.12
import SortFilterProxyModel 0.2
import "utils.js" as Utils // some helper functions

// The details "view". Consists of some images, a bunch of textual info and a game list.
FocusScope {
    id: root

    // This will be set in the main theme file
    property var currentCollection

    // The list shows either every game of the collection or only the favorites.
    // Favorites are saved by Pegasus itself, the theme only toggles the flag.
    property bool favoritesOnly: false
    readonly property int favoriteCount: favoriteGames.count

    SortFilterProxyModel {
        id: favoriteGames
        sourceModel: currentCollection.games
        filters: ValueFilter { roleName: "favorite"; value: true }
    }
    SortFilterProxyModel {
        id: shownGames
        sourceModel: currentCollection.games
        filters: ValueFilter { roleName: "favorite"; value: true; enabled: root.favoritesOnly }
    }

    // Shortcuts for the game list's currently selected game. currentGameIndex is
    // the row in the (maybe filtered) list, currentSourceIndex the collection's index.
    property alias currentGameIndex: gameList.currentIndex
    readonly property int currentSourceIndex: {
        shownGames.count; root.favoritesOnly; // re-evaluate when the list changes
        // While the filter switches the list may briefly have no selection
        return Math.max(0, shownGames.mapToSource(currentGameIndex));
    }
    readonly property var currentGame: currentCollection.games.get(currentSourceIndex)

    // Set by the main theme before restoring, to select that game once
    property string restoreTitle: ""

    // Show only the favorites by default if the collection has any. A game
    // restored from the last session is always shown, even if not a favorite.
    function applyDefaultFilter() {
        const games = currentCollection.games;
        let sourceIndex = currentSourceIndex;
        let mustShow = false;
        if (restoreTitle !== "") {
            sourceIndex = -1;
            for (let i = 0; i < games.count; i++) {
                if (games.get(i).title === restoreTitle) {
                    sourceIndex = i;
                    mustShow = true;
                    break;
                }
            }
            restoreTitle = "";
        }

        favoritesOnly = favoriteCount > 0;
        if (mustShow && favoritesOnly && !games.get(sourceIndex).favorite)
            favoritesOnly = false;
        selectSourceIndex(sourceIndex);
    }

    function selectSourceIndex(sourceIndex) {
        const row = sourceIndex >= 0 ? shownGames.mapFromSource(sourceIndex) : -1;
        currentGameIndex = row >= 0 ? row : 0;
        gameList.positionViewAtIndex(currentGameIndex, ListView.Center);
    }

    function toggleFavoritesOnly() {
        if (!favoritesOnly && favoriteCount === 0)
            return;
        const sourceIndex = currentSourceIndex;
        favoritesOnly = !favoritesOnly;
        selectSourceIndex(sourceIndex);
    }

    onCurrentCollectionChanged: Qt.callLater(applyDefaultFilter)
    onFocusChanged: if (focus) Qt.callLater(applyDefaultFilter)
    // Unfavoriting the last favorite would leave an empty list
    onFavoriteCountChanged: if (favoritesOnly && favoriteCount === 0) favoritesOnly = false

    // Nothing particularly interesting, see CollectionsView for more comments
    width: parent.width
    height: parent.height
    enabled: focus
    visible: y < parent.height

    signal cancel
    signal nextCollection
    signal prevCollection
    signal launchGame

    // Button hints show only the gamepad or only the keyboard, depending on
    // which one was used last (Pegasus can't tell if a gamepad is connected).
    // "" = not known yet, both are shown.
    property string inputMode: api.memory.get('inputMode') || ""
    readonly property var hintKeys: [
        api.keys.accept, api.keys.cancel, api.keys.filters, api.keys.details,
        api.keys.prevPage, api.keys.nextPage, api.keys.pageUp, api.keys.pageDown
    ]

    function setInputMode(mode) {
        if (mode !== inputMode) {
            inputMode = mode;
            api.memory.set('inputMode', mode);
        }
    }

    function updateInputMode(event) {
        // The D-pad arrives as arrow keys; Pegasus sends those without a
        // hardware scan code, while a real keyboard always has one
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down
                || event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            setInputMode(event.nativeScanCode === 0 ? "pad" : "keyboard");
            return;
        }
        for (const list of hintKeys) {
            for (let i = 0; i < list.length; i++) {
                if (list[i].key === event.key) {
                    setInputMode(list[i].name().startsWith("Gamepad") ? "pad" : "keyboard");
                    return;
                }
            }
        }
    }

    // The first gamepad button and keyboard key bound to an action, as text
    function keyName(list, pad) {
        for (let i = 0; i < list.length; i++) {
            const name = list[i].name();
            if (name.startsWith("Gamepad") !== pad)
                continue;
            if (!pad)
                return name === "Return" ? "Enter" : name;
            // Gamepad names look like "Gamepad0 (A)", keep the button name
            const match = name.match(/\(([^)]+)\)/);
            return match ? match[1] : name.substring(7);
        }
        return "";
    }
    function keyHint(list) {
        const pad = keyName(list, true);
        const kbd = keyName(list, false);
        if (inputMode === "pad" || !kbd) return pad;
        if (inputMode === "keyboard" || !pad) return kbd;
        return pad + " / " + kbd;
    }
    function keyPairHint(first, second) {
        const pad = keyName(first, true) + "/" + keyName(second, true);
        const kbd = keyName(first, false) + "/" + keyName(second, false);
        if (inputMode === "pad") return pad;
        if (inputMode === "keyboard") return kbd;
        return pad + " · " + kbd;
    }

    // Restart the video when the selected game changes or the view gets/loses focus
    // Called later, so it sees the new game (bindings like media.hasVideo may not be
    // updated yet in this handler) and runs once if the game changes several times
    // in a row, eg. when switching systems
    onCurrentGameChanged: Qt.callLater(media.reload)
    onEnabledChanged: Qt.callLater(media.reload)

    // Key handling. In addition, pressing left/right also moves to the prev/next collection.
    Keys.onLeftPressed: prevCollection()
    Keys.onRightPressed: nextCollection()
    Keys.onPressed: {
        // Page up/down jump by one screen of the list (holding repeats)
        if (api.keys.isPageDown(event)) {
            event.accepted = true;
            gameList.currentIndex = Math.min(gameList.count - 1, gameList.currentIndex + gameList.rowsPerPage);
            return;
        }
        if (api.keys.isPageUp(event)) {
            event.accepted = true;
            gameList.currentIndex = Math.max(0, gameList.currentIndex - gameList.rowsPerPage);
            return;
        }

        if (event.isAutoRepeat)
            return;

        if (api.keys.isAccept(event)) {
            event.accepted = true;
            launchGame();
            return;
        }
        if (api.keys.isCancel(event)) {
            event.accepted = true;
            cancel();
            return;
        }
        if (api.keys.isNextPage(event)) {
            event.accepted = true;
            nextCollection();
            return;
        }
        if (api.keys.isPrevPage(event)) {
            event.accepted = true;
            prevCollection();
            return;
        }
        if (api.keys.isFilters(event)) {
            event.accepted = true;
            if (!currentGame)
                return;
            // Unfavoriting the last favorite: switch to all games, staying on this one
            const sourceIndex = currentSourceIndex;
            const wasLast = favoritesOnly && favoriteCount === 1 && currentGame.favorite;
            currentGame.favorite = !currentGame.favorite;
            if (wasLast) {
                favoritesOnly = false;
                selectSourceIndex(sourceIndex);
            }
            return;
        }
        if (api.keys.isDetails(event)) {
            event.accepted = true;
            toggleFavoritesOnly();
            return;
        }
    }

    // Colors of the dark look; the accent marks the selection, stars and Launch key
    readonly property color clrAccent: "#ff8a3d"

    // Blurred game art behind the whole screen (the system's art if the game
    // has none), darkened by gradients so the light text stays readable
    Rectangle {
        anchors.fill: parent
        color: "#15161a"
    }
    Image {
        id: bgImage
        anchors.fill: parent
        asynchronous: true
        source: currentGame.assets.background ||
                currentGame.assets.screenshot ||
                currentGame.assets.boxFront ||
                (currentCollection.shortName ? "bg/%1_art_blur.png".arg(currentCollection.shortName) : "")
        sourceSize { width: 480; height: 480 }
        fillMode: Image.PreserveAspectCrop
        visible: false
    }
    FastBlur {
        anchors.fill: parent
        source: bgImage
        radius: 48
        visible: bgImage.status === Image.Ready
    }
    // Dark on the left where the text is, lighter towards the right
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0.03, 0.03, 0.05, 0.78) }
            GradientStop { position: 0.58; color: Qt.rgba(0.03, 0.03, 0.05, 0.25) }
        }
    }
    // Top and bottom fades under the header and footer
    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: parent.height * 0.18
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.03, 0.03, 0.05, 0.85) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
    Rectangle {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: parent.height * 0.14
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0.03, 0.03, 0.05, 0.9) }
        }
    }
    RadialGradient {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.35; color: "transparent" }
            GradientStop { position: 0.75; color: Qt.rgba(0, 0, 0, 0.45) }
        }
    }

    // The header on the top, with the collection's logo (in white, mostly), name and game count
    Item {
        id: header

        readonly property int paddingH: vpx(30) // H as horizontal
        readonly property int paddingV: vpx(22) // V as vertical

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: vpx(115)

        Image {
            id: headerLogo
            height: vpx(52)
            width: vpx(380) // so wide logos don't get too big
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left; leftMargin: header.paddingH
            }
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft
            // Render the SVG at (twice) the shown size, some are tiny and would be blurry scaled up
            sourceSize.height: height * 2
            mipmap: true
            readonly property string logoStyle: Utils.logoStyle(currentCollection.shortName)
            // Shown as is only if painting it white would ruin it
            visible: logoStyle === "color"

            source: currentCollection.shortName ? "logo/%1.svg".arg(currentCollection.shortName) : ""
            asynchronous: true
        }
        ColorOverlay {
            anchors.fill: headerLogo
            source: headerLogo
            color: "#fff"
            visible: headerLogo.logoStyle === "white"
        }
        // Dark, colorless parts (the lettering) turned white, colored parts kept
        ShaderEffect {
            anchors.fill: headerLogo
            visible: headerLogo.logoStyle === "lighten"
            property variant source: ShaderEffectSource { sourceItem: headerLogo }
            fragmentShader: "
                varying highp vec2 qt_TexCoord0;
                uniform sampler2D source;
                uniform lowp float qt_Opacity;
                void main() {
                    lowp vec4 c = texture2D(source, qt_TexCoord0);
                    lowp vec3 rgb = c.a > 0.0 ? c.rgb / c.a : c.rgb;
                    lowp float hi = max(rgb.r, max(rgb.g, rgb.b));
                    lowp float sat = hi - min(rgb.r, min(rgb.g, rgb.b));
                    lowp float k = (1.0 - smoothstep(0.1, 0.3, sat)) * (1.0 - smoothstep(0.3, 0.6, hi));
                    gl_FragColor = vec4(mix(rgb, vec3(1.0), k) * c.a, c.a) * qt_Opacity;
                }"
        }

        Text {
            text: "%1  ·  %2 GAMES".arg(currentCollection.name).arg(currentCollection.games.count)
            elide: Text.ElideLeft
            font.capitalization: Font.AllUppercase
            font.family: "Open Sans"
            font.pixelSize: vpx(20)
            horizontalAlignment: Text.AlignRight
            color: Qt.rgba(1, 1, 1, 0.67)

            width: parent.width * 0.45
            anchors {
                verticalCenter: parent.verticalCenter
                right: parent.right; rightMargin: header.paddingH
            }
        }
    }

    Item {
        id: content
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top

        readonly property int paddingH: vpx(30)
        readonly property int paddingV: vpx(40)

        // Layout: text on the left (details on top, description below),
        // media on the right (video on top, boxart below).
        readonly property real textLeft: paddingH
        readonly property real mediaRight: gameList.x - paddingH - vpx(40) // gap to the list panel
        readonly property int topRowHeight: vpx(280)
        readonly property int rowGap: vpx(30)

        // Fixed area reserved for the video, so the text never moves
        Item {
            id: mediaArea
            anchors {
                top: parent.top; topMargin: content.paddingV
                right: parent.right; rightMargin: parent.width - content.mediaRight
            }
            width: (content.mediaRight - content.textLeft) * 0.5
            height: content.topRowHeight
        }

        // Game name split into a main title and a subtitle ("Main : Sub" or "Main - Sub")
        readonly property var titleParts: {
            const t = currentGame ? currentGame.title : "";
            for (const sep of [" : ", " - "]) {
                const i = t.indexOf(sep);
                if (i > 0)
                    return [t.substring(0, i), t.substring(i + sep.length)];
            }
            return [t, ""];
        }
        readonly property real textRight: mediaArea.x - paddingH

        // Small accent line above the title: developer and year
        Text {
            id: metaText
            anchors {
                top: mediaArea.top; topMargin: -vpx(4)
                left: parent.left; leftMargin: content.textLeft
            }
            width: content.textRight - content.textLeft
            text: [currentGame.developer || currentGame.publisher,
                   currentGame.releaseYear > 0 ? currentGame.releaseYear : ""]
                  .filter(function(s) { return !!s; }).join("  ·  ")
            elide: Text.ElideRight
            font.family: "Open Sans"
            font.pixelSize: vpx(13)
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            color: root.clrAccent
        }

        // Title, cut with "..." if too long; a star in front for favorites
        Text {
            id: favoriteStar
            anchors { left: parent.left; leftMargin: content.textLeft; verticalCenter: titleText.verticalCenter }
            visible: currentGame.favorite
            width: visible ? implicitWidth + vpx(8) : 0
            text: "★"
            font.pixelSize: vpx(26)
            color: root.clrAccent
        }
        Text {
            id: titleText
            anchors { top: metaText.bottom; left: favoriteStar.right }
            width: content.textRight - favoriteStar.x - favoriteStar.width
            text: content.titleParts[0]
            elide: Text.ElideRight
            font.family: "Open Sans"
            font.pixelSize: vpx(30)
            font.weight: Font.DemiBold
            color: "#fff"
        }
        Text {
            id: subtitleText
            anchors {
                top: titleText.bottom
                left: parent.left; leftMargin: content.textLeft
                right: titleText.right
            }
            height: text ? implicitHeight : 0
            text: content.titleParts[1]
            elide: Text.ElideRight
            font.family: "Open Sans"
            font.pixelSize: vpx(18)
            font.weight: Font.Light
            color: Qt.rgba(1, 1, 1, 0.67)
        }

        // Rating as five (partly) filled stars and a number
        Row {
            id: ratingRow
            anchors {
                top: subtitleText.bottom; topMargin: vpx(8)
                left: parent.left; leftMargin: content.textLeft
            }
            spacing: vpx(10)

            Row {
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: 5
                    Item {
                        width: vpx(20)
                        height: vpx(22)
                        Text {
                            anchors.centerIn: parent
                            text: "★"
                            font.pixelSize: vpx(20)
                            color: Qt.rgba(1, 1, 1, 0.25)
                        }
                        Item {
                            width: parent.width * Math.max(0, Math.min(1, currentGame.rating * 5 - index))
                            height: parent.height
                            clip: true
                            Text {
                                x: (vpx(20) - width) / 2
                                anchors.verticalCenter: parent.verticalCenter
                                text: "★"
                                font.pixelSize: vpx(20)
                                color: root.clrAccent
                            }
                        }
                    }
                }
            }
            // LaunchBox rating (x-rating keeps the decimals the whole-percent rating loses)
            // and its vote count (x-votes)
            Text {
                readonly property var extra: currentGame ? currentGame.extra : null
                readonly property real exact: extra ? parseFloat(extra["rating"] || extra["x-rating"]) : NaN
                readonly property int votes: extra ? (parseInt(extra["votes"] || extra["x-votes"]) || 0) : 0
                anchors.verticalCenter: parent.verticalCenter
                visible: currentGame.rating > 0
                text: (isNaN(exact) ? currentGame.rating * 5 : exact).toFixed(1)
                font.family: "Open Sans"
                font.pixelSize: vpx(16)
                font.weight: Font.DemiBold
                color: "#fff"

                Text {
                    anchors { left: parent.right; leftMargin: vpx(6); baseline: parent.baseline }
                    visible: parent.votes > 0
                    text: "(" + String(parent.votes).replace(/\B(?=(\d{3})+(?!\d))/g, ",") + ")"
                    font.family: "Open Sans"
                    font.pixelSize: vpx(14)
                    color: Qt.rgba(1, 1, 1, 0.5)
                }
            }
        }

        // Game details: dim small labels, bright values cut with "..." if too long
        Grid {
            id: gameDetails
            anchors {
                top: ratingRow.bottom; topMargin: vpx(12)
                left: parent.left; leftMargin: content.textLeft
            }
            columns: 2

            Repeater {
                model: [
                    "Released", Utils.formatDate(currentGame.release) || "unknown",
                    "Developer", currentGame.developer || "unknown",
                    "Publisher", currentGame.publisher || "unknown",
                    "Genre", currentGame.genre || "unknown",
                    "Players", Utils.formatPlayers(currentGame.players),
                    "Last played", Utils.formatLastPlayed(currentGame.lastPlayed),
                    "Play time", Utils.formatPlayTime(currentGame.playTime)
                ]
                Text {
                    readonly property bool isLabel: index % 2 === 0
                    width: isLabel ? vpx(110) : content.textRight - content.textLeft - vpx(110)
                    height: vpx(25)
                    verticalAlignment: Text.AlignVCenter
                    text: modelData
                    elide: Text.ElideRight
                    font.family: "Open Sans"
                    font.pixelSize: isLabel ? vpx(14) : vpx(17)
                    font.weight: isLabel ? Font.DemiBold : Font.Normal
                    font.capitalization: isLabel ? Font.AllUppercase : Font.MixedCase
                    color: isLabel ? Qt.rgba(1, 1, 1, 0.47) : "#fff"
                }
            }
        }

        // Game video on the top right, always playing. The box is sized right
        // away, so it never changes size while a game is selected: to the
        // video's own aspect ratio if the metadata has it (x-video-aspect,
        // measured beforehand), else to the system's screen aspect ratio.
        // The box is black until the video plays, then the video fades in.
        // Games without a video show their screenshot instead.
        // Soft shadow under the video box
        RectangularGlow {
            visible: media.visible
            x: media.x + vpx(4)
            y: media.y + vpx(8)
            width: media.width
            height: media.height
            glowRadius: vpx(14)
            spread: 0.1
            cornerRadius: vpx(10) + glowRadius
            color: Qt.rgba(0, 0, 0, 0.55)
        }
        Rectangle {
            id: media
            anchors { top: mediaArea.top; right: mediaArea.right }

            // Rounded corners, the video included
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: media.width
                    height: media.height
                    radius: vpx(10)
                }
            }

            readonly property real aspectRatio: {
                const extra = currentGame ? currentGame.extra : null;
                const measured = extra ? parseFloat(extra["video-aspect"] || extra["x-video-aspect"]) : NaN;
                if (measured > 0)
                    return measured;
                if (boxAsMedia)
                    return boxProbe.implicitWidth / boxProbe.implicitHeight;
                return Utils.screenAspect(currentCollection.shortName);
            }

            width: Math.min(mediaArea.height * aspectRatio, mediaArea.width)
            height: width / aspectRatio
            color: "#000"

            readonly property bool hasVideo: !!(currentGame && currentGame.assets.video)
            // No video and no screenshot, but a landscape box image (arcade title/snap
            // pictures, e.g. CPS1/CPS2): that image takes the video's place and the
            // boxart slot below stays empty
            readonly property bool hasScreenshot: !!(currentGame && currentGame.assets.screenshot)
            readonly property bool boxAsMedia: !hasVideo && !hasScreenshot && boxProbe.status === Image.Ready
                                               && boxProbe.implicitWidth > boxProbe.implicitHeight * 1.2
            // No video, screenshot or landscape box: hide the box instead of showing it black
            visible: hasVideo || hasScreenshot || boxAsMedia

            function reload() {
                videoFadeIn.stop();
                gameVideo.opacity = 0;
                gameVideo.stop();
                gameVideo.source = "";
                if (root.enabled && currentGame && currentGame.assets.video)
                    videoDelay.restart();
                else
                    videoDelay.stop();
            }

            // Only looks at the box image while the game has no video or screenshot
            Image {
                id: boxProbe
                asynchronous: true
                source: (!media.hasVideo && !media.hasScreenshot && currentGame) ? currentGame.assets.boxFront : ""
                visible: false
            }

            Image {
                anchors.fill: parent
                asynchronous: true
                source: media.boxAsMedia ? currentGame.assets.boxFront : currentGame.assets.screenshot
                sourceSize { width: 512; height: 512 }
                fillMode: Image.PreserveAspectFit
                visible: !media.hasVideo
            }

            Video {
                id: gameVideo
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectFit
                loops: MediaPlayer.Infinite
                muted: true
                opacity: 0

                onPlaybackStateChanged: {
                    if (playbackState === MediaPlayer.PlayingState)
                        videoFadeIn.restart();
                }

                NumberAnimation {
                    id: videoFadeIn
                    target: gameVideo
                    property: "opacity"
                    from: 0; to: 1
                    duration: 250
                }

                // Short wait so fast scrolling doesn't load every video on the way
                Timer {
                    id: videoDelay
                    interval: 100
                    onTriggered: {
                        gameVideo.source = currentGame.assets.video;
                        gameVideo.play();
                    }
                }
            }
        }

        // Boxart below the video, aligned to the same right edge
        Item {
            id: boxart
            anchors {
                top: mediaArea.bottom; topMargin: content.rowGap
                right: mediaArea.right
                bottom: parent.bottom; bottomMargin: content.paddingV
            }
            // Only as wide as the image itself, so the description can use the rest
            width: Math.min(height * boxartImage.aspectRatio, vpx(200))

            Image {
                id: boxartImage
                readonly property real aspectRatio: (implicitWidth / implicitHeight) || 0
                anchors.fill: parent
                asynchronous: true
                source: media.boxAsMedia ? "" : (currentGame.assets.boxFront ||
                        currentGame.assets.logo ||
                        currentGame.assets.marquee)
                sourceSize { width: 256; height: 256 } // optimization (max size)
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignRight
                verticalAlignment: Image.AlignTop
                visible: false
            }
            // Rounded corners on the painted part of the image, then a shadow
            Item {
                id: boxartMask
                anchors.fill: boxartImage
                visible: false
                Rectangle {
                    x: boxartImage.width - boxartImage.paintedWidth
                    width: boxartImage.paintedWidth
                    height: boxartImage.paintedHeight
                    radius: vpx(6)
                }
            }
            OpacityMask {
                id: boxartRounded
                anchors.fill: boxartImage
                source: boxartImage
                maskSource: boxartMask
                visible: false
            }
            DropShadow {
                anchors.fill: boxartImage
                source: boxartRounded
                horizontalOffset: vpx(3)
                verticalOffset: vpx(6)
                radius: vpx(14)
                samples: 29
                color: Qt.rgba(0, 0, 0, 0.6)
            }
        }

        // Game description below the details, scrolling up automatically
        Item {
            id: descriptionBox
            anchors {
                top: mediaArea.bottom; topMargin: content.rowGap
                left: parent.left; leftMargin: content.textLeft
                right: boxart.left; rightMargin: vpx(15)
                bottom: parent.bottom; bottomMargin: content.paddingV
            }
            clip: true

            readonly property real overflow: Math.max(0, gameDescription.contentHeight - height)

            function restartScroll() {
                scrollAnim.stop();
                gameDescription.y = 0;
                if (overflow > 0)
                    scrollAnim.start();
            }

            onOverflowChanged: restartScroll()

            GameInfoText {
                id: gameDescription
                width: parent.width

                text: currentGame.description
                font.pixelSize: vpx(16)
                font.weight: Font.Normal
                font.capitalization: Font.MixedCase
                color: Qt.rgba(1, 1, 1, 0.85)
                lineHeight: 1.15
                wrapMode: Text.WordWrap
                elide: Text.ElideNone

                onTextChanged: descriptionBox.restartScroll()
            }

            // Pause at the top, scroll to the end, pause, then jump back to the top
            SequentialAnimation {
                id: scrollAnim
                loops: Animation.Infinite

                PauseAnimation { duration: 3000 }
                NumberAnimation {
                    target: gameDescription; property: "y"
                    from: 0; to: -descriptionBox.overflow
                    duration: Math.max(1, descriptionBox.overflow / vpx(20) * 1000)
                }
                PauseAnimation { duration: 3000 }
                PropertyAction { target: gameDescription; property: "y"; value: 0 }
            }
        }

        // Translucent panel behind the game list, from the top of the screen
        Rectangle {
            id: listPanel
            anchors {
                top: parent.top; topMargin: -header.height
                bottom: parent.bottom
                right: parent.right
                left: gameList.left; leftMargin: -content.paddingH
            }
            color: Qt.rgba(0, 0, 0, 0.43)

            // Soft shadow and a thin highlight line on the left edge
            Rectangle {
                anchors { top: parent.top; bottom: parent.bottom; right: parent.left }
                width: vpx(10)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.2) }
                }
            }
            Rectangle {
                anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                width: vpx(1)
                color: Qt.rgba(1, 1, 1, 0.2)
            }
        }

        ListView {
            id: gameList
            width: parent.width * 0.35
            anchors {
                top: parent.top; topMargin: content.paddingV
                right: parent.right; rightMargin: content.paddingH
                bottom: parent.bottom; bottomMargin: content.paddingV
            }
            //clip: true

            focus: true

            // The list gets every key first and consumes up/down itself, so the
            // input mode is checked here (without accepting the event)
            Keys.onPressed: root.updateInputMode(event)

            // How many rows fit on screen, for page up/down
            readonly property int rowsPerPage: currentItem ? Math.max(1, Math.floor(height / currentItem.height)) : 1

            // The view doesn't scroll while hidden (eg. when restoring the
            // position on startup), so scroll to the selection when shown
            onVisibleChanged: if (visible) positionViewAtIndex(currentIndex, ListView.Center)

            model: shownGames
            delegate: Rectangle {
                readonly property bool selected: ListView.isCurrentItem
                readonly property color clrDark: "#141418"
                readonly property color clrLight: "#e1e1e6"

                width: ListView.view.width
                height: gameTitle.height
                radius: vpx(4)
                color: selected ? root.clrAccent : "transparent"

                Text {
                    id: gameTitle
                    text: (modelData.favorite ? "★ " : "") + modelData.title
                    color: parent.selected ? parent.clrDark : parent.clrLight
                    // Rows further from the middle of the list fade out a little
                    // (by position, so rows scrolled in with the mouse look normal)
                    opacity: parent.selected ? 1.0
                             : Math.max(0.3, 1.0 - Math.abs(parent.y - gameList.contentY + parent.height / 2
                                                            - gameList.height / 2) / parent.height * 0.05)

                    font.pixelSize: vpx(20)
                    font.weight: parent.selected ? Font.DemiBold : Font.Normal
                    font.family: "Open Sans"

                    lineHeight: 1.2
                    verticalAlignment: Text.AlignVCenter

                    width: parent.width
                    elide: Text.ElideRight
                    leftPadding: vpx(10)
                    rightPadding: leftPadding
                }

                // Click selects the game, double click launches it
                MouseArea {
                    anchors.fill: parent
                    onClicked: gameList.currentIndex = index
                    onDoubleClicked: {
                        gameList.currentIndex = index;
                        root.launchGame();
                    }
                }
            }

            highlightRangeMode: ListView.ApplyRange
            highlightMoveDuration: 0
            preferredHighlightBegin: height * 0.5 - vpx(15)
            preferredHighlightEnd: height * 0.5 + vpx(15)
        }
    }

    Item {
        id: footer
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: vpx(25) * 1.5

        // On the left, only while the list is filtered (the header already
        // shows the total count)
        Text {
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left; leftMargin: header.paddingH
            }
            visible: root.favoritesOnly
            text: "★ FAVORITES  %1 / %2".arg(shownGames.count).arg(currentCollection.games.count)
            font.family: "Open Sans"
            font.pixelSize: vpx(13)
            color: Qt.rgba(1, 1, 1, 0.75)
        }

        // Button hints on the right: gamepad button / keyboard key, then the action
        Row {
            anchors {
                verticalCenter: parent.verticalCenter
                right: parent.right; rightMargin: header.paddingH
            }
            spacing: vpx(18)

            Repeater {
                // Key names come from the Pegasus key settings
                model: [
                    { keys: keyHint(api.keys.accept), label: "LAUNCH", main: true },
                    { keys: keyHint(api.keys.cancel), label: "BACK" },
                    { keys: keyHint(api.keys.filters), label: currentGame && currentGame.favorite ? "UNFAVORITE" : "FAVORITE" },
                    { keys: keyHint(api.keys.details), label: root.favoritesOnly ? "SHOW ALL" : "FAVORITES ONLY" },
                    { keys: keyPairHint(api.keys.pageUp, api.keys.pageDown), label: "PAGE" },
                    { keys: keyPairHint(api.keys.prevPage, api.keys.nextPage), label: "SYSTEM" }
                ]

                Row {
                    spacing: vpx(6)
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: keyText.width + vpx(10)
                        height: keyText.height + vpx(2)
                        radius: vpx(3)
                        // The Launch key stands out in the accent color
                        color: modelData.main ? root.clrAccent : Qt.rgba(1, 1, 1, 0.16)

                        Text {
                            id: keyText
                            anchors.centerIn: parent
                            text: modelData.keys
                            font.family: "Open Sans"
                            font.pixelSize: vpx(11)
                            color: modelData.main ? "#141418" : "#e8e9ea"
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        font.family: "Open Sans"
                        font.pixelSize: vpx(12)
                        color: Qt.rgba(1, 1, 1, 0.75)
                    }
                }
            }
        }
    }
}
