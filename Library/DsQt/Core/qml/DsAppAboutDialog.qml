import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Window {
    id: aboutWindow
    title: "About " + (Qt.application.name ? Qt.application.name : "Application")
    width: 480
    height: 320
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    color: "#2b2b2b"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12

        Label {
            text: Qt.application.name ? Qt.application.name : "Application"
            font.pixelSize: 18
            font.bold: true
            color: "#ffffff"
        }

        Label {
            text: Qt.application.version ? ("Version " + Qt.application.version) : "Version not specified"
            font.pixelSize: 13
            color: "#cccccc"
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#444444"
        }

        GridLayout {
            columns: 2
            rowSpacing: 8
            columnSpacing: 14
            Layout.fillWidth: true

            Label {
                text: "DsQt Library:"
                color: "#aaaaaa"
                font.pixelSize: 12
            }
            TextEdit {
                text: Ds.env ? Ds.env.dsqtGitVersion() : ""
                readOnly: true
                selectByMouse: true
                color: "#ffffff"
                font.pixelSize: 12
                font.family: "monospace"
                Layout.fillWidth: true
            }

            Label {
                text: "Qt Runtime:"
                color: "#aaaaaa"
                font.pixelSize: 12
            }
            Label {
                text: "Qt " + (typeof dsqtQtVersion === "string" ? dsqtQtVersion : "6.x")
                color: "#ffffff"
                font.pixelSize: 12
            }

            Label {
                text: "Process ID:"
                color: "#aaaaaa"
                font.pixelSize: 12
            }
            Label {
                text: "" + (Qt.application.pid ? Qt.application.pid : "")
                color: "#ffffff"
                font.pixelSize: 12
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }

            Button {
                text: "Copy Details"
                onClicked: {
                    var details = (Qt.application.name ? Qt.application.name : "Application") + " v" + Qt.application.version + "\n"
                        + "DsQt: " + (Ds.env ? Ds.env.dsqtGitVersion() : "") + "\n"
                        + "PID: " + Qt.application.pid;
                    // Qt.application.clipboard can vary across platforms; fallback cleanly
                    try {
                        dummyClipboard.text = details;
                        dummyClipboard.selectAll();
                        dummyClipboard.copy();
                    } catch (e) {
                        console.log("About dialog details:\n" + details);
                    }
                }
            }

            Button {
                text: "Close"
                onClicked: aboutWindow.close()
            }
        }
    }

    TextEdit {
        id: dummyClipboard
        visible: false
    }
}
