import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import "DockStyle.js" as DS

PlasmoidItem {
    id: root

    Plasmoid.status: PlasmaCore.Types.PassiveStatus
    Plasmoid.icon: "docker"
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

    property var statsMeta: null
    property var statsList: []
    property bool statsLoading: false
    property string statsError: ""
    property var analysis: null
    property bool analysisLoading: false
    property string analysisError: ""
    property var topData: null
    property bool topLoading: false
    property string topError: ""

    compactRepresentation: CompactRepresentation {}

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    fullRepresentation: Rectangle {
        id: popupBody
        implicitWidth: 430
        clip: true
        color: DS.cardBg
        radius: 8
        border.width: 1
        border.color: DS.border

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

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: headerRow.implicitHeight + Kirigami.Units.smallSpacing
                color: DS.headerBg
                radius: 4

                RowLayout {
                    id: headerRow
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        source: Qt.resolvedUrl("../images/docker.svg")
                    }

                    Text {
                        text: root.headerTitle()
                        font.bold: true
                        color: DS.text
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: 13
                    }

                    ChipButton {
                        id: statsChip
                        visible: plasmoid.configuration.showStatsChip !== false
                            && root.currentPage === 0 && root.statsMeta !== null
                            && root.statsMeta.available === true
                            && root.statsList.length > 0
                        text: root.statsChipText()
                        accent: true
                        maxTextWidth: 130
                        onClicked: root.openStats()
                    }

                    IconButton {
                        icon: Qt.resolvedUrl("../images/icons/chart.svg")
                        tooltip: i18n("Consumo")
                        onClicked: root.openStats()
                    }

                    IconButton {
                        icon: Qt.resolvedUrl("../images/icons/sparkle.svg")
                        tooltip: i18n("Análisis")
                        onClicked: root.openAnalysis()
                    }

                    IconButton {
                        icon: Qt.resolvedUrl("../images/icons/gear.svg")
                        tooltip: i18n("Configurar widget")
                        onClicked: Plasmoid.internalAction("configure").trigger()
                    }


IconButton {
                        icon: Qt.resolvedUrl("../images/icons/refresh.svg")
                        tooltip: i18n("Actualizar")
                        onClicked: root.fetchContainers()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: DS.divider
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
                                color: DS.subText
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
                                color: DS.subText
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
                                color: DS.subText
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
                    onTopRequested: root.openTop()
                }

                LogsView {
                    id: logsView
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

                StatsView {
                    anchors.fill: parent
                    visible: root.currentPage === 4
                    stats: root.statsList
                    meta: root.statsMeta
                    loading: root.statsLoading
                    error: root.statsError
                    onBack: root.currentPage = 0
                    onRefreshRequested: root.fetchStats(true)
                    onOpenDetail: function(name) { root.openDetail(name); }
                }

                AnalysisView {
                    anchors.fill: parent
                    visible: root.currentPage === 5
                    analysis: root.analysis
                    loading: root.analysisLoading
                    error: root.analysisError
                    onBack: root.currentPage = 0
                    onRefreshRequested: root.fetchAnalysis(true)
                    onRequestMaintain: function(target, title, subtitle, confirmText) {
                        root.requestMaintain(target, title, subtitle, confirmText);
                    }
                }

                TopView {
                    anchors.fill: parent
                    visible: root.currentPage === 6
                    containerName: root.currentContainer ? root.currentContainer.name : ""
                    processData: root.topData
                    loading: root.topLoading
                    error: root.topError
                    onBack: root.currentPage = 1
                    onRefreshRequested: root.fetchTop(true)
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
                    color: DS.danger
                }

                Text {
                    text: root.lastError
                    color: DS.danger
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }

                ChipButton {
                    text: i18n("Reintentar")
                    accent: true
                    onClicked: root.fetchContainers()
                }
            }
        }

        Rectangle {
            id: busyOverlay
            anchors.fill: parent
            visible: root.busy
            color: Qt.rgba(0.082, 0.082, 0.086, 0.72)
            z: 10

            Text {
                anchors.centerIn: parent
                text: i18n("Ejecutando…")
                color: DS.text
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
            }
        }

        Rectangle {
            id: confirmOverlay
            anchors.fill: parent
            visible: root.pendingConfirm !== null
            color: Qt.rgba(0.082, 0.082, 0.086, 0.96)
            z: 11

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width * 0.85
                spacing: Kirigami.Units.largeSpacing

                Text {
                    text: root.pendingConfirm ? root.pendingConfirm.title : ""
                    color: DS.text
                    font.bold: true
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
                }

                Text {
                    text: root.pendingConfirm ? root.pendingConfirm.subtitle : ""
                    color: DS.danger
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Kirigami.Units.smallSpacing

                    ChipButton {
                        text: i18n("Cancelar")
                        onClicked: root.pendingConfirm = null
                    }

                    ChipButton {
                        text: root.pendingConfirm ? root.pendingConfirm.confirmText : ""
                        accent: true
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

    // `docker stats` tarda ~2s: solo se mide con la página de consumo abierta
    // y el backend cachea 10s para que pulsar a la vez no dispare dos procesos.
    Timer {
        id: statsTimer
        interval: Math.max(5, Math.min(120, plasmoid.configuration.statsInterval || 10)) * 1000
        repeat: true
        running: root.expanded && root.currentPage === 4
        onTriggered: root.fetchStats(false)
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
        function onStatsIntervalChanged() {
            statsTimer.restart();
        }
    }

    onExpandedChanged: {
        if (plasmoid.expanded) {
            root.fetchContainers();
            root.fetchStats(false);
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
        xhr.timeout = 20000;
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
        xhr.timeout = 30000;
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
        // `docker ps -a` puede tardar 1-3 s si el dockerd va cargado: con 3 s de
        // margen el widget se quedaba vacío sin avisar.
        xhr.timeout = 15000;
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

    function headerTitle() {
        if (root.currentPage === 4) {
            return i18n("Consumo");
        }
        if (root.currentPage === 5) {
            return i18n("Análisis");
        }
        if (root.currentPage === 3 && root.currentStack) {
            return root.currentStack.title;
        }
        if ((root.currentPage === 1 || root.currentPage === 2 || root.currentPage === 6)
                && root.currentContainer) {
            return root.currentContainer.name;
        }
        return i18n("Contenedores");
    }

    function statsChipText() {
        if (!root.statsList || root.statsList.length === 0) {
            return "";
        }
        var top = root.statsList[0];
        var name = top.name || "";
        if (name.length > 16) {
            name = name.substring(0, 15) + "…";
        }
        return name + " " + (top.cpu || 0).toFixed(1) + " %";
    }

    function openStats() {
        root.currentPage = 4;
        root.fetchStats(false);
    }

    function openAnalysis() {
        root.currentPage = 5;
        root.fetchAnalysis(false);
    }

    function openTop() {
        root.topData = null;
        root.topError = "";
        root.currentPage = 6;
        root.fetchTop(false);
    }

    function fetchStats(force) {
        if (root.statsLoading) {
            return;
        }
        root.statsLoading = true;
        var url = root.backendUrl + "/api/stats" + (force ? "?refresh=1" : "");
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.timeout = 35000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            root.statsLoading = false;
            if (xhr.status !== 200) {
                root.statsError = i18n("No se pudo medir el consumo");
                return;
            }
            var d;
            try {
                d = JSON.parse(xhr.responseText);
            } catch (err) {
                root.statsError = i18n("Respuesta inválida");
                return;
            }
            if (d.ok === false) {
                root.statsError = d.error || i18n("Error del backend");
                return;
            }
            root.statsError = "";
            root.statsMeta = d;
            root.statsList = d.stats || [];
        };
        xhr.ontimeout = function() {
            root.statsLoading = false;
            root.statsError = i18n("Tiempo de espera agotado");
        };
        xhr.onerror = function() {
            root.statsLoading = false;
            root.statsError = i18n("Sin conexión con el backend");
        };
        xhr.send();
    }

    function fetchAnalysis(force) {
        if (root.analysisLoading) {
            return;
        }
        root.analysisLoading = true;
        var url = root.backendUrl + "/api/analysis" + (force ? "?refresh=1" : "");
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.timeout = 90000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            root.analysisLoading = false;
            if (xhr.status !== 200) {
                root.analysisError = i18n("No se pudo completar el análisis");
                return;
            }
            var d;
            try {
                d = JSON.parse(xhr.responseText);
            } catch (err) {
                root.analysisError = i18n("Respuesta inválida");
                return;
            }
            if (d.ok === false) {
                root.analysisError = d.error || i18n("Error del backend");
                return;
            }
            root.analysisError = "";
            root.analysis = d;
        };
        xhr.ontimeout = function() {
            root.analysisLoading = false;
            root.analysisError = i18n("Tiempo de espera agotado");
        };
        xhr.onerror = function() {
            root.analysisLoading = false;
            root.analysisError = i18n("Sin conexión con el backend");
        };
        xhr.send();
    }

    function fetchTop(force) {
        var name = root.currentContainer ? root.currentContainer.name : "";
        if (!name) {
            return;
        }
        root.topLoading = true;
        root.topError = "";
        var url = root.backendUrl + "/api/containers/" + encodeURIComponent(name) + "/top"
            + (force ? "?refresh=1" : "");
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.timeout = 20000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            root.topLoading = false;
            if (xhr.status !== 200) {
                root.topError = i18n("No se pudieron leer los procesos");
                return;
            }
            var d;
            try {
                d = JSON.parse(xhr.responseText);
            } catch (err) {
                root.topError = i18n("Respuesta inválida");
                return;
            }
            if (d.ok === false) {
                root.topError = d.error || i18n("Error del backend");
                return;
            }
            root.topData = d.top || null;
        };
        xhr.ontimeout = function() {
            root.topLoading = false;
            root.topError = i18n("Tiempo de espera agotado");
        };
        xhr.onerror = function() {
            root.topLoading = false;
            root.topError = i18n("Sin conexión con el backend");
        };
        xhr.send();
    }

    function requestMaintain(target, title, subtitle, confirmText) {
        if (root.busy) {
            return;
        }
        root.pendingConfirm = {
            title: title,
            subtitle: subtitle,
            confirmText: confirmText,
            run: function() { root.doMaintain(target); }
        };
    }

    function doMaintain(target) {
        root.busy = true;
        root.lastError = "";
        var xhr = new XMLHttpRequest();
        xhr.open("POST", root.backendUrl + "/api/maintain/" + encodeURIComponent(target));
        xhr.timeout = 300000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            root.busy = false;
            var d = null;
            try {
                d = JSON.parse(xhr.responseText);
            } catch (e) {}
            if (xhr.status !== 200 || !d || d.ok === false) {
                root.lastError = (d && d.error) || i18n("No se pudo completar la limpieza");
            } else {
                root.lastError = "";
            }
            root.fetchAnalysis(true);
            root.fetchStats(true);
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