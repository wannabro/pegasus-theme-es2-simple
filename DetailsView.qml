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
    onCurrentGameChanged: media.reload()
    onEnabledChanged: media.reload()

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

    // The header ba on the top, with the collection's logo and name
    Rectangle {
        id: header

        readonly property int paddingH: vpx(30) // H as horizontal
        readonly property int paddingV: vpx(22) // V as vertical

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: vpx(115)
        color: "#c5c6c7"

        Image {
            height: parent.height - header.paddingV * 2
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left; leftMargin: header.paddingH
                right: parent.horizontalCenter; rightMargin: header.paddingH
            }
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft

            source: currentCollection.shortName ? "logo/%1.svg".arg(currentCollection.shortName) : ""
            asynchronous: true
        }

        Text {
            text: currentCollection.name
            wrapMode: Text.WordWrap
            font.capitalization: Font.AllUppercase
            font.family: "Open Sans"
            font.pixelSize: vpx(32)
            font.weight: Font.Light // this is how you use the light variant
            horizontalAlignment: Text.AlignRight
            color: "#7b7d7f"

            width: parent.width * 0.35
            anchors {
                verticalCenter: parent.verticalCenter
                right: parent.right; rightMargin: header.paddingH
            }
        }
    }

    Rectangle {
        id: content
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        color: "#97999a"

        readonly property int paddingH: vpx(30)
        readonly property int paddingV: vpx(40)

        // Blurred game art in the background, tinted with the base gray so the
        // dark text stays readable
        Image {
            id: bgImage
            anchors.fill: parent
            asynchronous: true
            source: currentGame.assets.background ||
                    currentGame.assets.screenshot ||
                    currentGame.assets.boxFront
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
        Rectangle {
            anchors.fill: parent
            color: content.color
            opacity: 0.75
        }

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

        // Game name above the details, cut with "..." if too long
        GameInfoText {
            id: titleText
            anchors {
                top: mediaArea.top
                left: parent.left; leftMargin: content.textLeft
                right: mediaArea.left; rightMargin: content.paddingH
            }
            text: (currentGame.favorite ? "★ " : "") + currentGame.title
            font.pixelSize: vpx(28)
            font.weight: Font.Normal
            font.capitalization: Font.MixedCase
        }

        // While the game details could be a grid, I've separated them to two
        // separate columns to manually control thw width of the second one below.
        Column {
            id: gameLabels
            anchors {
                top: titleText.bottom; topMargin: vpx(8)
                left: parent.left; leftMargin: content.textLeft
            }

            GameInfoText { text: "Rating:" }
            GameInfoText { text: "Released:" }
            GameInfoText { text: "Developer:" }
            GameInfoText { text: "Publisher:" }
            GameInfoText { text: "Genre:" }
            GameInfoText { text: "Players:" }
            GameInfoText { text: "Last played:" }
            GameInfoText { text: "Play time:" }
        }

        Column {
            id: gameDetails
            anchors {
                top: gameLabels.top
                left: gameLabels.right; leftMargin: content.paddingH
                right: mediaArea.left; rightMargin: content.paddingH
            }

            // 'width' is set so if the text is too long it will be cut. I also use some
            // JavaScript code to make some text pretty.
            RatingBar { percentage: currentGame.rating }
            GameInfoText { width: parent.width; text: Utils.formatDate(currentGame.release) || "unknown" }
            GameInfoText { width: parent.width; text: currentGame.developer || "unknown" }
            GameInfoText { width: parent.width; text: currentGame.publisher || "unknown" }
            GameInfoText { width: parent.width; text: currentGame.genre || "unknown" }
            GameInfoText { width: parent.width; text: Utils.formatPlayers(currentGame.players) }
            GameInfoText { width: parent.width; text: Utils.formatLastPlayed(currentGame.lastPlayed) }
            GameInfoText { width: parent.width; text: Utils.formatPlayTime(currentGame.playTime) }
        }

        // Game video on the top right, always playing. The box is sized to the
        // system's screen aspect ratio right away, so it never changes size
        // while a game is selected. The screenshot is shown until the video
        // plays, and for games without a video.
        Rectangle {
            id: media
            anchors { top: mediaArea.top; right: mediaArea.right }

            readonly property real aspectRatio: Utils.screenAspect(currentCollection.shortName)

            width: Math.min(mediaArea.height * aspectRatio, mediaArea.width)
            height: width / aspectRatio
            color: "#000"

            function reload() {
                gameVideo.stop();
                gameVideo.source = "";
                if (root.enabled && currentGame && currentGame.assets.video)
                    videoDelay.restart();
                else
                    videoDelay.stop();
            }

            Image {
                anchors.fill: parent
                asynchronous: true
                source: currentGame.assets.screenshot
                sourceSize { width: 512; height: 512 }
                fillMode: Image.PreserveAspectFit
                visible: gameVideo.playbackState !== MediaPlayer.PlayingState
            }

            Video {
                id: gameVideo
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectFit
                loops: MediaPlayer.Infinite
                muted: true
                visible: playbackState === MediaPlayer.PlayingState

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
                source: currentGame.assets.boxFront ||
                        currentGame.assets.logo ||
                        currentGame.assets.marquee
                sourceSize { width: 256; height: 256 } // optimization (max size)
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignRight
                verticalAlignment: Image.AlignTop
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

        // Translucent full-height panel behind the game list
        Rectangle {
            id: listPanel
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
                left: gameList.left; leftMargin: -content.paddingH
            }
            color: Qt.rgba(0, 0, 0, 0.35)

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
                readonly property color clrDark: "#393a3b"
                readonly property color clrLight: "#e8e9ea"

                width: ListView.view.width
                height: gameTitle.height
                color: selected ? Qt.rgba(1, 1, 1, 0.85) : "transparent"

                Text {
                    id: gameTitle
                    text: (modelData.favorite ? "★ " : "") + modelData.title
                    color: parent.selected ? parent.clrDark : parent.clrLight

                    font.pixelSize: vpx(20)
                    font.capitalization: Font.AllUppercase
                    font.family: "Open Sans"

                    lineHeight: 1.2
                    verticalAlignment: Text.AlignVCenter

                    width: parent.width
                    elide: Text.ElideRight
                    leftPadding: vpx(10)
                    rightPadding: leftPadding
                }
            }

            highlightRangeMode: ListView.ApplyRange
            highlightMoveDuration: 0
            preferredHighlightBegin: height * 0.5 - vpx(15)
            preferredHighlightEnd: height * 0.5 + vpx(15)
        }
    }

    Rectangle {
        id: footer
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: vpx(25) * 1.5
        color: header.color

        // Which games the list shows, on the left
        Text {
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left; leftMargin: header.paddingH
            }
            text: root.favoritesOnly
                  ? "★ FAVORITES  %1 / %2".arg(shownGames.count).arg(currentCollection.games.count)
                  : "ALL GAMES  %1".arg(shownGames.count)
            font.family: "Open Sans"
            font.pixelSize: vpx(13)
            color: "#393a3b"
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
                    { keys: keyHint(api.keys.accept), label: "LAUNCH" },
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
                        color: "#393a3b"

                        Text {
                            id: keyText
                            anchors.centerIn: parent
                            text: modelData.keys
                            font.family: "Open Sans"
                            font.pixelSize: vpx(11)
                            color: "#e8e9ea"
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        font.family: "Open Sans"
                        font.pixelSize: vpx(12)
                        color: "#393a3b"
                    }
                }
            }
        }
    }
}
