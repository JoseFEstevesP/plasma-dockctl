import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    Plasmoid.status: PlasmaCore.Types.PassiveStatus
    Plasmoid.icon: "system-run"
    toolTipMainText: i18n("Contenedores Docker")
    toolTipSubText: root.lastError
        ? i18n("Backend no disponible")
        : i18n("%1 en marcha · %2 detenidos", root.runningCount, root.stoppedCount)
    hideOnWindowDeactivate: true

    property int runningCount: 0
    property int stoppedCount: 0
    property int unhealthyCount: 0
    property var containers: []
    property var stacks: []
    property bool loading: true
    property bool busy: false
    property var pendingConfirm: null
    property string lastError: ""
    property string backendUrl: "http://127.0.0.1:" + (plasmoid.configuration.backendPort || 8427)

    readonly property int maxPopupHeight: Math.round(Screen.height * 0.7)
    readonly property int minPopupHeight: 140
    readonly property int fixedContentHeight: 400

    property int currentPage: 0
    property var currentContainer: null
    property var currentStack: null
    property var detailData: null
    property bool detailLoading: false
    property string detailError: ""
    property string logs: ""
    property bool logsLoading: false
    property string logsError: ""

    compactRepresentation: CompactRepresentation {}

    fullRepresentation: Rectangle {
        id: popupBody
        implicitWidth: 430
        clip: true
        color: "transparent"

        readonly property int marginTotal: Kirigami.Units.largeSpacing * 2
        readonly property int sepHeight: Kirigami.Units.smallSpacing * 2
        readonly property int contentHeight: root.currentPage === 0
            ? Math.max(48, rowsCol.implicitHeight)
            : root.fixedContentHeight

        implicitHeight: Math.max(root.minPopupHeight, Math.min(root.maxPopupHeight,
            marginTotal + headerRow.implicitHeight + sepHeight + contentHeight
            + (errRow.visible ? errRow.implicitHeight : 0)))

        ColumnLayout {
            id: bodyLayout
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                id: headerRow
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    source: Qt.resolvedUrl("../images/docker.svg")
                }

                Text {
                    text: i18n("Contenedores Docker")
                    font.bold: true
                    color: Kirigami.Theme.textColor
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
                }

                Text {
                    text: root.runningCount + " / " + (root.runningCount + root.stoppedCount)
                    color: Kirigami.Theme.textColor
                    opacity: 0.7
                    Layout.alignment: Qt.AlignVCenter
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }

                PlasmaComponents.ToolButton {
                    hoverEnabled: true
                    icon.name: "configure"
                    Controls.ToolTip.visible: hovered
                    Controls.ToolTip.text: i18n("Configurar widget")
                    onClicked: Plasmoid.internalAction("configure").trigger()
                }

                PlasmaComponents.ToolButton {
                    hoverEnabled: true
                    icon.name: "view-refresh"
                    Controls.ToolTip.visible: hovered
                    Controls.ToolTip.text: i18n("Actualizar")
                    onClicked: root.fetchContainers()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Kirigami.Theme.textColor
                opacity: 0.15
            }

            Item {
                id: contentArea
                Layout.fillWidth: true
                Layout.fillHeight: true

                Flickable {
                    id: listScroll
                    anchors.fill: parent
                    visible: root.currentPage === 0
                    clip: true
                    contentWidth: width
                    contentHeight: rowsCol.implicitHeight
                    interactive: rowsCol.implicitHeight > height

                    ColumnLayout {
                        id: rowsCol
                        width: listScroll.width
                        spacing: 4

                        Repeater {
                            model: root.stacks

                            delegate: StackSection {
                                stack: modelData
                                onOpenStack: function(key) { root.openStack(key); }
                            }
                        }

                        Item {
                            visible: root.loading
                            Layout.preferredHeight: Kirigami.Units.smallSpacing * 8
                            Layout.fillWidth: true
                            Text {
                                anchors.centerIn: parent
                                text: i18n("Cargando contenedores…")
                                color: Kirigami.Theme.textColor
                                opacity: 0.6
                                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
                            }
                        }

                        Item {
                            visible: !root.loading && !root.lastError && root.containers.length === 0
                            Layout.preferredHeight: Kirigami.Units.smallSpacing * 8
                            Layout.fillWidth: true
                            Text {
                                anchors.centerIn: parent
                                text: i18n("Sin contenedores")
                                color: Kirigami.Theme.textColor
                                opacity: 0.6
                                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
                            }
                        }

                        Item {
                            visible: !root.loading && !root.lastError && root.stacks.length === 0 && root.containers.length > 0
                            Layout.preferredHeight: Kirigami.Units.smallSpacing * 8
                            Layout.fillWidth: true
                            Text {
                                anchors.centerIn: parent
                                text: i18n("Ninguno en marcha")
                                color: Kirigami.Theme.textColor
                                opacity: 0.6
                                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
                            }
                        }
                    }
                }

                ContainerDetail {
                    anchors.fill: parent
                    visible: root.currentPage === 1
                    container: root.currentContainer
                    detailData: root.detailData
                    loading: root.detailLoading
                    error: root.detailError
                    onBack: root.currentPage = 0
                    onRefreshRequested: root.fetchDetail(root.currentContainer ? root.currentContainer.name : "")
                    onRequestAction: function(name, action) { root.requestAction(name, action); }
                    onOpenLogs: function(name) { root.openLogs(name); }
                }

                LogsView {
                    anchors.fill: parent
                    visible: root.currentPage === 2
                    containerName: root.currentContainer ? root.currentContainer.name : ""
                    logs: root.logs
                    loading: root.logsLoading
                    error: root.logsError
                    onBack: root.currentPage = 1
                    onRefreshRequested: root.fetchLogs(root.currentContainer ? root.currentContainer.name : "")
                }

                StackDetail {
                    anchors.fill: parent
                    visible: root.currentPage === 3
                    stack: root.currentStack
                    onBack: root.currentPage = 0
                    onRefreshRequested: root.fetchContainers()
                    onOpenDetail: function(name) { root.openDetail(name); }
                    onRequestAction: function(name, action) { root.requestAction(name, action); }
                    onRestartAll: root.requestRestartAll()
                }
            }

            RowLayout {
                id: errRow
                visible: root.lastError !== ""
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    source: "dialog-error"
                }

                Text {
                    text: root.lastError
                    color: Kirigami.Theme.negativeTextColor
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }

                PlasmaComponents.Button {
                    text: i18n("Reintentar")
                    onClicked: root.fetchContainers()
                }
            }
        }

        Rectangle {
            id: busyOverlay
            anchors.fill: parent
            visible: root.busy
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r,
                           Kirigami.Theme.backgroundColor.g,
                           Kirigami.Theme.backgroundColor.b, 0.7)
            z: 10

            Text {
                anchors.centerIn: parent
                text: i18n("Ejecutando…")
                color: Kirigami.Theme.textColor
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
            }
        }

        Rectangle {
            id: confirmOverlay
            anchors.fill: parent
            visible: root.pendingConfirm !== null
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r,
                           Kirigami.Theme.backgroundColor.g,
                           Kirigami.Theme.backgroundColor.b, 0.94)
            z: 11

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width * 0.85
                spacing: Kirigami.Units.largeSpacing

                Text {
                    text: root.pendingConfirm ? root.pendingConfirm.title : ""
                    color: Kirigami.Theme.textColor
                    font.bold: true
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
                }

                Text {
                    text: root.pendingConfirm ? root.pendingConfirm.subtitle : ""
                    color: Kirigami.Theme.negativeTextColor
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Button {
                        text: i18n("Cancelar")
                        onClicked: root.pendingConfirm = null
                    }

                    PlasmaComponents.Button {
                        text: root.pendingConfirm ? root.pendingConfirm.confirmText : ""
                        onClicked: {
                            var pc = root.pendingConfirm;
                            root.pendingConfirm = null;
                            if (pc && pc.run) {
                                pc.run();
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: pollTimer
        interval: Math.max(1, (plasmoid.configuration.refreshInterval || 5)) * 1000
        repeat: true
        running: root.expanded
        onTriggered: root.fetchContainers()
    }

    Connections {
        target: plasmoid.configuration
        function onShowStoppedChanged() {
            root.buildStacks();
        }
        function onBackendPortChanged() {
            root.backendUrl = "http://127.0.0.1:" + (plasmoid.configuration.backendPort || 8427);
            root.fetchContainers();
        }
    }

    onExpandedChanged: {
        if (plasmoid.expanded) {
            root.fetchContainers();
        }
    }

    function buildStacks() {
        var showStopped = plasmoid.configuration.showStopped !== false;
        var groups = {};
        var order = [];
        for (var i = 0; i < root.containers.length; i++) {
            var c = root.containers[i];
            if (!showStopped && !c.running) {
                continue;
            }
            var key = c.stack || "";
            if (!groups[key]) {
                groups[key] = { containers: [], running: 0 };
                order.push(key);
            }
            groups[key].containers.push(c);
            if (c.running) {
                groups[key].running++;
            }
        }
        var arr = [];
        for (var j = 0; j < order.length; j++) {
            var k = order[j];
            var g = groups[k];
            arr.push({
                key: k,
                title: k ? k : i18n("Otros"),
                containers: g.containers,
                running: g.running,
                total: g.containers.length
            });
        }
        arr.sort(function(a, b) {
            if (a.key === "") {
                return 1;
            }
            if (b.key === "") {
                return -1;
            }
            return a.key.localeCompare(b.key);
        });
        root.stacks = arr;
        if (root.currentStack) {
            for (var f = 0; f < root.stacks.length; f++) {
                if (root.stacks[f].key === root.currentStack.key) {
                    root.currentStack = root.stacks[f];
                    break;
                }
            }
        }
    }

    function openStack(key) {
        for (var i = 0; i < root.stacks.length; i++) {
            if (root.stacks[i].key === key) {
                root.currentStack = root.stacks[i];
                break;
            }
        }
        root.currentPage = 3;
    }

    function openDetail(name) {
        var c = null;
        for (var i = 0; i < root.containers.length; i++) {
            if (root.containers[i].name === name) {
                c = root.containers[i];
                break;
            }
        }
        root.currentContainer = c;
        root.currentPage = 1;
        root.fetchDetail(name);
    }

    function fetchDetail(name) {
        if (!name) {
            return;
        }
        root.detailLoading = true;
        root.detailError = "";
        var xhr = new XMLHttpRequest();
        xhr.open("GET", root.backendUrl + "/api/containers/" + encodeURIComponent(name));
        xhr.timeout = 5000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            root.detailLoading = false;
            if (xhr.status !== 200) {
                root.detailError = i18n("No se pudo obtener el detalle");
                return;
            }
            var d;
            try {
                d = JSON.parse(xhr.responseText);
            } catch (err) {
                root.detailError = i18n("Respuesta inválida");
                return;
            }
            if (d.ok) {
                root.detailData = d.detail;
            } else {
                root.detailError = d.error || i18n("Error del backend");
            }
        };
        xhr.ontimeout = function() {
            root.detailLoading = false;
            root.detailError = i18n("Tiempo de espera agotado");
        };
        xhr.onerror = function() {
            root.detailLoading = false;
            root.detailError = i18n("Sin conexión con el backend");
        };
        xhr.send();
    }

    function openLogs(name) {
        root.logs = "";
        root.logsError = "";
        root.currentPage = 2;
        root.fetchLogs(name);
    }

    function fetchLogs(name) {
        if (!name) {
            return;
        }
        root.logsLoading = true;
        root.logsError = "";
        var xhr = new XMLHttpRequest();
        xhr.open("GET", root.backendUrl + "/api/containers/" + encodeURIComponent(name) + "/logs?lines=300");
        xhr.timeout = 10000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            root.logsLoading = false;
            if (xhr.status !== 200) {
                root.logsError = i18n("No se pudieron leer los logs");
                return;
            }
            var d;
            try {
                d = JSON.parse(xhr.responseText);
            } catch (err) {
                root.logsError = i18n("Respuesta inválida");
                return;
            }
            if (d.ok) {
                root.logs = d.logs || "";
            } else {
                root.logsError = d.error || i18n("Error del backend");
            }
        };
        xhr.ontimeout = function() {
            root.logsLoading = false;
            root.logsError = i18n("Tiempo de espera agotado");
        };
        xhr.onerror = function() {
            root.logsLoading = false;
            root.logsError = i18n("Sin conexión con el backend");
        };
        xhr.send();
    }

    function fetchContainers() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", root.backendUrl + "/api/containers");
        xhr.timeout = 3000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            root.loading = false;
            if (xhr.status !== 200) {
                root.lastError = i18n("Servicio backend no disponible");
                return;
            }
            var d = JSON.parse(xhr.responseText);
            if (!d.ok) {
                root.lastError = d.error || i18n("Error del backend");
                return;
            }
            root.lastError = "";
            root.containers = d.containers;
            root.buildStacks();
            var run = 0;
            var stop = 0;
            var degrade = 0;
            for (var i = 0; i < d.containers.length; i++) {
                var c = d.containers[i];
                if (c.running) {
                    run++;
                    if (c.health && c.health !== "healthy") {
                        degrade++;
                    }
                } else {
                    stop++;
                }
            }
            root.runningCount = run;
            root.stoppedCount = stop;
            root.unhealthyCount = degrade;
        };
        xhr.ontimeout = function() {
            root.loading = false;
            root.lastError = i18n("Tiempo de espera agotado");
        };
        xhr.onerror = function() {
            root.loading = false;
            root.lastError = i18n("Sin conexión con el backend");
        };
        xhr.send();
    }

    function requestAction(name, action) {
        if (root.busy) {
            return;
        }
        if (action === "remove" && plasmoid.configuration.confirmRemove) {
            root.pendingConfirm = {
                title: i18n("¿Eliminar el contenedor «%1»?", name),
                subtitle: i18n("Esta acción es irreversible."),
                confirmText: i18n("Eliminar"),
                run: function() { root.doAction(name, "remove"); }
            };
            return;
        }
        doAction(name, action);
    }

    function requestRestartAll() {
        if (root.busy || !root.currentStack) {
            return;
        }
        var st = root.currentStack;
        root.pendingConfirm = {
            title: i18n("¿Reiniciar todos los contenedores de «%1»?", st.title),
            subtitle: i18n("Se reiniciarán %1 contenedores del stack.", st.containers.length),
            confirmText: i18n("Reiniciar"),
            run: function() { root.doRestartAll(st.key); }
        };
    }

    function doRestartAll(key) {
        root.busy = true;
        root.lastError = "";
        var xhr = new XMLHttpRequest();
        xhr.open("POST", root.backendUrl + "/api/stacks/" + encodeURIComponent(key) + "/restart");
        xhr.timeout = 60000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            root.busy = false;
            if (xhr.status !== 200) {
                root.lastError = i18n("No se pudo reiniciar el stack");
            } else {
                try {
                    var d = JSON.parse(xhr.responseText);
                    if (d.failed && d.failed.length > 0) {
                        root.lastError = i18n("%1 contenedores fallaron al reiniciar", d.failed.length);
                    }
                } catch (e) {}
            }
            root.fetchContainers();
        };
        xhr.ontimeout = function() {
            root.busy = false;
            root.lastError = i18n("Tiempo de espera agotado");
        };
        xhr.onerror = function() {
            root.busy = false;
            root.lastError = i18n("Sin conexión con el backend");
        };
        xhr.send();
    }

    function doAction(name, action) {
        root.busy = true;
        root.lastError = "";
        var xhr = new XMLHttpRequest();
        xhr.open("POST", root.backendUrl + "/api/containers/" + encodeURIComponent(name) + "/" + action);
        xhr.timeout = 15000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            root.busy = false;
            if (xhr.status !== 200) {
                var parsed = {};
                try {
                    parsed = JSON.parse(xhr.responseText);
                } catch (e) {}
                root.lastError = parsed.error || i18n("No se pudo %1 «%2»", action, name);
            } else {
                if (action === "remove" && root.currentPage === 1) {
                    root.currentPage = 0;
                } else if (root.currentPage === 1 && root.currentContainer && root.currentContainer.name === name) {
                    root.fetchDetail(name);
                }
            }
            root.fetchContainers();
        };
        xhr.ontimeout = function() {
            root.busy = false;
            root.lastError = i18n("Tiempo de espera agotado");
        };
        xhr.onerror = function() {
            root.busy = false;
            root.lastError = i18n("Sin conexión con el backend");
        };
        xhr.send();
    }
}