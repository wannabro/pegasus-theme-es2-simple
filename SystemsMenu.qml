import QtQuick 2.15

// Settings overlay for choosing which systems (collections) are shown.
// Lists every collection with a checkbox; the hidden ones are stored by
// the collections view, this menu only edits that list.
FocusScope {
    id: root

    // Set by the collections view
    property var hidden: []          // short names of the hidden collections
    property var hintSource          // provides keyHint(), see DetailsView

    signal toggled(string shortName)
    signal showAll
    signal closed

    readonly property int shownCount: {
        let n = 0;
        for (let i = 0; i < api.collections.count; i++)
            if (hidden.indexOf(api.collections.get(i).shortName) < 0)
                n++;
        return n;
    }

    anchors.fill: parent
    visible: focus

    Keys.onPressed: {
        if (event.isAutoRepeat)
            return;
        if (api.keys.isAccept(event)) {
            event.accepted = true;
            const c = api.collections.get(list.currentIndex);
            // Keep at least one system visible
            if (c && (hidden.indexOf(c.shortName) >= 0 || shownCount > 1))
                toggled(c.shortName);
            return;
        }
        if (api.keys.isFilters(event)) {
            event.accepted = true;
            showAll();
            return;
        }
        if (api.keys.isCancel(event) || api.keys.isDetails(event)) {
            event.accepted = true;
            closed();
            return;
        }
    }

    // Dim the screen behind the menu
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: vpx(620)
        height: parent.height * 0.85
        radius: vpx(6)
        color: "#e8e9ea"

        Text {
            id: title
            anchors { top: parent.top; topMargin: vpx(18); horizontalCenter: parent.horizontalCenter }
            text: "SYSTEMS"
            font.family: "Open Sans"
            font.pixelSize: vpx(26)
            color: "#393a3b"
        }

        ListView {
            id: list
            anchors {
                top: title.bottom; topMargin: vpx(12)
                left: parent.left; leftMargin: vpx(16)
                right: parent.right; rightMargin: vpx(16)
                bottom: footer.top; bottomMargin: vpx(8)
            }
            clip: true
            focus: true
            model: api.collections

            // The list gets every key first and consumes up/down itself
            Keys.onPressed: if (root.hintSource) root.hintSource.updateInputMode(event)
            highlightMoveDuration: 0
            highlightRangeMode: ListView.ApplyRange
            preferredHighlightBegin: height * 0.5 - vpx(22)
            preferredHighlightEnd: height * 0.5 + vpx(22)

            delegate: Rectangle {
                readonly property bool selected: ListView.isCurrentItem
                readonly property bool shown: root.hidden.indexOf(modelData.shortName) < 0

                width: ListView.view.width
                height: vpx(44)
                radius: vpx(3)
                color: selected ? "#393a3b" : "transparent"

                Row {
                    anchors { left: parent.left; leftMargin: vpx(10); verticalCenter: parent.verticalCenter }
                    spacing: vpx(12)
                    opacity: shown ? 1.0 : 0.4

                    // Checkbox
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: vpx(20); height: width
                        radius: vpx(3)
                        color: "transparent"
                        border.width: vpx(2)
                        border.color: selected ? "#e8e9ea" : "#393a3b"

                        Text {
                            anchors.centerIn: parent
                            visible: shown
                            text: "✓"
                            font.pixelSize: vpx(16)
                            font.bold: true
                            color: selected ? "#e8e9ea" : "#393a3b"
                        }
                    }

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: vpx(90); height: vpx(30)
                        fillMode: Image.PreserveAspectFit
                        source: modelData.shortName ? "logo/%1.svg".arg(modelData.shortName) : ""
                        sourceSize { width: 256; height: 256 }
                        asynchronous: true
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: vpx(300)
                        text: modelData.name
                        elide: Text.ElideRight
                        font.family: "Open Sans"
                        font.pixelSize: vpx(18)
                        color: selected ? "#e8e9ea" : "#393a3b"
                    }
                }

                Text {
                    anchors { right: parent.right; rightMargin: vpx(12); verticalCenter: parent.verticalCenter }
                    text: modelData.games.count
                    font.family: "Open Sans"
                    font.pixelSize: vpx(15)
                    color: selected ? "#e8e9ea" : "#7b7d7f"
                }
            }
        }

        Item {
            id: footer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: vpx(44)

            Text {
                anchors { left: parent.left; leftMargin: vpx(20); verticalCenter: parent.verticalCenter }
                text: "%1 / %2 SHOWN".arg(root.shownCount).arg(api.collections.count)
                font.family: "Open Sans"
                font.pixelSize: vpx(14)
                color: "#393a3b"
            }
            Text {
                anchors { right: parent.right; rightMargin: vpx(20); verticalCenter: parent.verticalCenter }
                text: root.hintSource
                      ? "%1  TOGGLE     %2  SHOW ALL     %3  DONE"
                            .arg(root.hintSource.keyHint(api.keys.accept))
                            .arg(root.hintSource.keyHint(api.keys.filters))
                            .arg(root.hintSource.keyHint(api.keys.cancel))
                      : ""
                font.family: "Open Sans"
                font.pixelSize: vpx(14)
                color: "#393a3b"
            }
        }
    }
}
