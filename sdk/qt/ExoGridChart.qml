import QtQuick
import QtCharts

Rectangle {
    id: root
    width: 800
    height: 600
    color: "#f5f5f5"

    property string host: "localhost"
    property int port: 9090
    property alias connected: chartView.connected

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        Rectangle {
            width: parent.width
            height: 30
            color: root.connected ? "#4caf50" : "#f44336"
            radius: 4

            Text {
                anchors.centerIn: parent
                color: "white"
                font.bold: true
                text: root.connected ? "✓ Connected" : "✗ Disconnected"
            }
        }

        Row {
            spacing: 20

            Text {
                text: "Ticks: " + chartView.tickCount
                font.pointSize: 12
            }

            Text {
                text: "Volume: " + chartView.totalVolume
                font.pointSize: 12
            }

            Text {
                id: pocText
                text: "POC: $" + chartView.pocPrice.toFixed(2)
                font.pointSize: 12
            }
        }

        // Chart would go here
        Rectangle {
            width: parent.width
            height: parent.height - 80
            color: "white"
            border.color: "#ddd"

            Text {
                anchors.centerIn: parent
                text: "Market Profile Chart"
                font.pointSize: 16
                color: "#999"
            }
        }
    }

    // C++ backend connection
    function connect() {
        chartView.connect(host, port)
    }

    function disconnect() {
        chartView.disconnect()
    }

    function startStreaming(exchanges) {
        chartView.startStreaming(exchanges)
    }
}
