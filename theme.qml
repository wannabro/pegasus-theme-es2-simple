import QtQuick 2.0

// Welcome! This is the entry point of the theme; it defines two "views"
// and a way to move (and animate moving) between them.
FocusScope {
    // When the theme loads, try to restore the last selected collection, game
    // and view. The collection and game are looked up by name first, so they are
    // found even if the list of collections changed; the saved indices are only
    // used as fallback. If this is the first time launching this theme, these
    // values will be undefined, which is why there are zeroes as fallback.
    Component.onCompleted: {
        restorePosition();
        restoreReady = true;
    }
    // The theme is unloaded before Pegasus quits, so this saves the position
    // even if no game was launched
    Component.onDestruction: savePosition()

    property bool restoreReady: false

    function findIndex(model, role, value) {
        if (value === undefined)
            return -1;
        for (let i = 0; i < model.count; i++) {
            if (model.get(i)[role] === value)
                return i;
        }
        return -1;
    }

    function restorePosition() {
        const collectionIdx = findIndex(api.collections, 'name', api.memory.get('collectionName'));
        collectionsView.currentCollectionIndex = collectionIdx >= 0
            ? collectionIdx
            : (api.memory.get('collectionIndex') || 0);

        const gameIdx = findIndex(collectionsView.currentCollection.games, 'title', api.memory.get('gameTitle'));
        detailsView.currentGameIndex = gameIdx >= 0
            ? gameIdx
            : (api.memory.get('gameIndex') || 0);

        if (api.memory.get('view') === 'details')
            detailsView.focus = true;
    }

    function savePosition() {
        const collection = collectionsView.currentCollection;
        const game = detailsView.currentGame;

        api.memory.set('collectionIndex', collectionsView.currentCollectionIndex);
        api.memory.set('gameIndex', detailsView.currentGameIndex);
        api.memory.set('collectionName', collection ? collection.name : '');
        api.memory.set('gameTitle', game ? game.title : '');
        api.memory.set('view', detailsView.focus ? 'details' : 'collections');
    }

    // Also save shortly after the selection changes, in case Pegasus is not
    // closed normally (eg. killed or crashed)
    Timer {
        id: saveTimer
        interval: 1000
        onTriggered: savePosition()
    }
    Connections {
        target: collectionsView
        enabled: restoreReady
        function onCurrentCollectionIndexChanged() { saveTimer.restart(); }
    }
    Connections {
        target: detailsView
        enabled: restoreReady
        function onCurrentGameIndexChanged() { saveTimer.restart(); }
        function onFocusChanged() { saveTimer.restart(); }
    }

    // Loading the fonts here makes them usable in the rest of the theme
    // and can be referred to using their name and weight.
    FontLoader { source: "fonts/OPENSANS.TTF" }
    FontLoader { source: "fonts/OPENSANS-LIGHT.TTF" }

    // The actual views are defined in their own QML files. They activate
    // each other by setting the focus. The details view is glued to the bottom
    // of the collections view, and the collections view to the bottom of the
    // screen for animation purposes (see below).
    CollectionsView {
        id: collectionsView
        anchors.bottom: parent.bottom

        focus: true
        onCollectionSelected: detailsView.focus = true
    }
    DetailsView {
        id: detailsView
        anchors.top: collectionsView.bottom

        currentCollection: collectionsView.currentCollection

        onCancel: collectionsView.focus = true
        onNextCollection: collectionsView.selectNext()
        onPrevCollection: collectionsView.selectPrev()
        onLaunchGame: {
            savePosition();
            currentGame.launch();
        }
    }

    // I animate the collection view's bottom anchor to move it to the top of
    // the screen. This, in turn, pulls up the details view.
    states: [
        State {
            when: detailsView.focus
            AnchorChanges {
                target: collectionsView;
                anchors.bottom: parent.top
            }
        }
    ]
    // Add some animations. There aren't any complex State definitions so I just
    // set a generic smooth anchor animation to get the job done.
    transitions: Transition {
        AnchorAnimation {
            duration: 400
            easing.type: Easing.OutQuad
        }
    }
}
