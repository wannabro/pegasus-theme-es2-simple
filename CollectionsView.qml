import QtQuick 2.15
import SortFilterProxyModel 0.2
import "utils.js" as Utils

// The collections view consists of two carousels, one for the collection logo bar
// and one for the background images. They should have the same number of elements
// to be kept in sync.
FocusScope {
    id: root

    // This element has the same size as the whole screen (ie. its parent).
    // Because this screen itself will be moved around when a collection is
    // selected, I've used width/height instead of anchors.
    width: parent.width
    height: parent.height
    enabled: focus // do not receive key/mouse events when unfocused
    visible: y + height >= 0 // optimization: do not render the item when it's not on screen

    signal collectionSelected

    // Provides keyHint() for the button hints (the details view)
    property var hintSource

    // Systems hidden in the settings menu, by short name. Saved by the theme.
    property var hiddenCollections: api.memory.get('hiddenCollections') || []

    // Systems sorted by release year; all of them (for the settings menu) and
    // the shown ones (for the carousels). The sorter's expression can't see
    // the Utils import, so it goes through this function.
    function collectionLessThan(a, b) {
        return Utils.collectionLessThan(a, b);
    }

    SortFilterProxyModel {
        id: sortedCollections
        sourceModel: api.collections
        sorters: ExpressionSorter {
            expression: root.collectionLessThan(modelLeft, modelRight)
        }
    }
    SortFilterProxyModel {
        id: shownCollections
        sourceModel: api.collections
        filters: ExpressionFilter {
            expression: root.hiddenCollections.indexOf(model.shortName) < 0
        }
        sorters: ExpressionSorter {
            expression: root.collectionLessThan(modelLeft, modelRight)
        }
    }

    // Shortcut for the currently selected collection. They will be used
    // by the Details view too, for example to show the collection's logo.
    // currentCollectionIndex is the position among the shown systems.
    property alias currentCollectionIndex: logoAxis.currentIndex
    readonly property var currentCollection: {
        shownCollections.count; // re-evaluate when the shown systems change
        return api.collections.get(Math.max(0, shownCollections.mapToSource(logoAxis.currentIndex)));
    }

    // Selects a system by its name; returns false if it's not shown
    function selectCollectionByName(name) {
        for (let i = 0; i < api.collections.count; i++) {
            if (api.collections.get(i).name !== name)
                continue;
            const row = shownCollections.mapFromSource(i);
            if (row < 0)
                return false;
            logoAxis.currentIndex = row;
            return true;
        }
        return false;
    }

    function setHidden(list) {
        hiddenCollections = list;
        api.memory.set('hiddenCollections', list);
    }

    function openSystemsMenu() {
        systemsMenu.selectedName = currentCollection ? currentCollection.name : "";
        systemsMenu.focus = true;
    }
    function closeSystemsMenu() {
        logoAxis.focus = true;
        // Stay on the same system if it's still shown
        if (!selectCollectionByName(systemsMenu.selectedName))
            logoAxis.currentIndex = Math.min(logoAxis.currentIndex, shownCollections.count - 1);
    }

    // These functions can be called by other elements of the theme if the collection
    // has to be changed manually. See the connection between the Collection and
    // Details views in the main theme file.
    function selectNext() {
        logoAxis.incrementCurrentIndex();
    }
    function selectPrev() {
        logoAxis.decrementCurrentIndex();
    }

    // The carousel of background images. This isn't the item we control with the keys,
    // however it reacts to mouse and so should still update the Index.
    Carousel {
        id: bgAxis

        anchors.fill: parent
        itemWidth: width

        model: shownCollections
        delegate: bgAxisItem
        currentIndex: logoAxis.currentIndex

        highlightMoveDuration: 500 // it's moving a little bit slower than the main bar
    }
    Component {
        // Either the image for the collection or a single colored rectangle
        id: bgAxisItem

        Item {
            width: root.width
            height: root.height
            visible: PathView.onPath // optimization: do not draw if not visible

            Rectangle {
                anchors.fill: parent
                color: "#777"
                visible: realBg.status != Image.Ready // optimization: only draw if the image did not load (yet)
            }
            Image {
                id: realBg
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop // fill the screen without black bars
                source: modelData.shortName ? "bg/%1_art_blur.png".arg(modelData.shortName) : ""
                asynchronous: true
            }
        }
    }

    // I've put the main bar's parts inside this wrapper item to change the opacity
    // of the background separately from the carousel. You could also use a Rectangle
    // with a color that has alpha value.
    Item {
        id: logoBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: vpx(170)

        // Background
        Rectangle {
            anchors.fill: parent
            color: "#fff"
            opacity: 0.85
        }
        // The main carousel that we actually control
        Carousel {
            id: logoAxis

            anchors.fill: parent
            itemWidth: vpx(480)

            model: shownCollections
            delegate: CollectionLogo {
                longName: modelData.name
                shortName: modelData.shortName
            }

            focus: true

            Keys.onPressed: {
                if (root.hintSource)
                    root.hintSource.updateInputMode(event);
                if (event.isAutoRepeat)
                    return;

                if (api.keys.isNextPage(event)) {
                    event.accepted = true;
                    incrementCurrentIndex();
                }
                else if (api.keys.isPrevPage(event)) {
                    event.accepted = true;
                    decrementCurrentIndex();
                }
                else if (api.keys.isDetails(event)) {
                    event.accepted = true;
                    root.openSystemsMenu();
                }
            }

            onItemSelected: root.collectionSelected()
        }
    }

    // Console photos below the game count, moving together with the logo bar.
    // The selected one is large, the neighbours small and faded.
    Carousel {
        id: deviceAxis

        anchors {
            left: parent.left
            right: parent.right
            top: countBar.bottom; topMargin: vpx(10)
            bottom: parent.bottom; bottomMargin: vpx(10)
        }
        itemWidth: logoAxis.itemWidth // same spacing, so each photo sits under its logo

        model: shownCollections
        delegate: Item {
            readonly property bool selected: PathView.isCurrentItem

            width: deviceAxis.itemWidth
            height: deviceAxis.height
            visible: PathView.onPath

            opacity: selected ? 1.0 : 0.45
            Behavior on opacity { NumberAnimation { duration: 150 } }

            // Every photo gets about the same area, so wide ones (eg. a console
            // next to its arcade stick) don't look much bigger than tall ones
            Image {
                id: deviceImage
                readonly property real aspect: implicitHeight > 0 ? implicitWidth / implicitHeight : 1
                readonly property real targetArea: vpx(165) * vpx(165)
                readonly property real fitWidth: Math.min(Math.sqrt(targetArea * aspect),
                                                          parent.width * 0.8,
                                                          parent.height * 0.85 * aspect)

                anchors.centerIn: parent
                width: fitWidth
                height: fitWidth / aspect
                fillMode: Image.PreserveAspectFit
                source: Utils.deviceImage(modelData.shortName)
                sourceSize { width: 512; height: 512 }
                asynchronous: true

                scale: parent.selected ? 1.0 : 0.6
                Behavior on scale { NumberAnimation { duration: 200 } }
            }
        }
        currentIndex: logoAxis.currentIndex
        interactive: false // follows the logo bar only, so they never get out of sync
    }

    // Game count bar -- like above, I've put it in an Item to separately control opacity
    Item {
        id: countBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: logoBar.bottom
        height: label.height * 1.5

        Rectangle {
            anchors.fill: parent
            color: "#ddd"
            opacity: 0.85
        }

        Text {
            id: label
            anchors.centerIn: parent
            text: "%1 GAMES AVAILABLE".arg(currentCollection.games.count)
            color: "#333"
            font.pixelSize: vpx(25)
            font.family: "Open Sans"
        }
    }

    // Button hint for the settings menu, bottom right (gamepad or keyboard,
    // whichever was used last, like in the details view)
    Item {
        anchors { right: parent.right; rightMargin: vpx(30); bottom: parent.bottom; bottomMargin: vpx(16) }
        width: hintRow.width
        height: hintRow.height
        visible: !!root.hintSource

        Row {
            id: hintRow
            spacing: vpx(6)

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: keyText.width + vpx(10)
                height: keyText.height + vpx(2)
                radius: vpx(3)
                color: "#393a3b"

                Text {
                    id: keyText
                    anchors.centerIn: parent
                    text: root.hintSource ? root.hintSource.keyHint(api.keys.details) : ""
                    font.family: "Open Sans"
                    font.pixelSize: vpx(11)
                    color: "#e8e9ea"
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "SYSTEMS"
                font.family: "Open Sans"
                font.pixelSize: vpx(12)
                // Light text with a dark edge, readable on any background art
                color: "#e8e9ea"
                style: Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.6)
            }
        }
    }

    SystemsMenu {
        id: systemsMenu

        property string selectedName: "" // system selected when the menu was opened

        model: sortedCollections
        hidden: root.hiddenCollections
        hintSource: root.hintSource

        onToggled: {
            const list = root.hiddenCollections.slice();
            const i = list.indexOf(shortName);
            if (i >= 0)
                list.splice(i, 1);
            else
                list.push(shortName);
            root.setHidden(list);
        }
        onShowAll: root.setHidden([])
        onClosed: root.closeSystemsMenu()
    }
}
