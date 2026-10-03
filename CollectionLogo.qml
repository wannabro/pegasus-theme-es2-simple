import QtQuick 2.0

// The collection logo on the collection carousel. Just an image that gets scaled
// and more visible when selected. Also has a fallback text if there's no image.
Item {
    property string longName: "" // set on the PathView side
    property string shortName: "" // set on the PathView side
    readonly property bool selected: PathView.isCurrentItem

    width: vpx(480)
    height: vpx(120)
    visible: PathView.onPath // optimization: do not draw if not visible

    opacity: selected ? 1.0 : 0.5
    Behavior on opacity { NumberAnimation { duration: 150 } }


    // Every logo gets about the same area, so long wordmarks don't look much
    // bigger than square-ish ones
    Image {
        id: image
        readonly property real aspect: implicitHeight > 0 ? implicitWidth / implicitHeight : 4
        readonly property real targetArea: vpx(150) * vpx(150)
        readonly property real fitWidth: Math.min(Math.sqrt(targetArea * aspect),
                                                  parent.width * 0.8,
                                                  parent.height * 0.9 * aspect)

        anchors.centerIn: parent
        width: fitWidth
        height: fitWidth / aspect
        fillMode: Image.PreserveAspectFit

        source: shortName ? "logo/%1.svg".arg(shortName) : ""
        asynchronous: true
        sourceSize { width: 256; height: 256 } // optimization: render SVGs in at most 256x256

        scale: selected ? 1.0 : 0.66
        Behavior on scale { NumberAnimation { duration: 200 } }
    }

    Text {
        id: label
        anchors.centerIn: parent
        color: "#000"
        font.family: "Open Sans"
        font.pixelSize: vpx(50)
        text: shortName || longName

        visible: image.status != Image.Ready

        scale: selected ? 1.5 : 1.0
        Behavior on scale { NumberAnimation { duration: 150 } }
    }
}
