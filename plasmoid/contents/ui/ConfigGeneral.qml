import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Kirigami.FormLayout {
    id: page

    property alias cfg_refreshInterval: refreshSpin.value
    property alias cfg_backendPort: portSpin.value
    property alias cfg_confirmRemove: confirmRemove.checked
    property alias cfg_showStopped: showStopped.checked

    PlasmaComponents.SpinBox {
        id: refreshSpin
        Kirigami.FormData.label: i18n("Intervalo de refresco (segundos):")
        from: 1
        to: 120
        stepSize: 1
        editable: true
    }

    PlasmaComponents.SpinBox {
        id: portSpin
        Kirigami.FormData.label: i18n("Puerto del backend:")
        from: 1024
        to: 65535
        stepSize: 1
        editable: true
    }

    PlasmaComponents.CheckBox {
        id: confirmRemove
        Kirigami.FormData.label: i18n("Confirmar antes de eliminar un contenedor:")
    }

    PlasmaComponents.CheckBox {
        id: showStopped
        Kirigami.FormData.label: i18n("Mostrar contenedores detenidos:")
    }
}