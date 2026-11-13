# Reproductor Taskbar

Prototipo para simular un reproductor de musica en la zona de la taskbar de Windows, sin instalar Windhawk ni modificar Explorer.

## Que hace

- Abre una ventana chica, sin borde, siempre visible y con fondo #1C1C1C.
- Se posiciona abajo a la izquierda, sobre la zona visual de la taskbar cuando esta abajo.
- Se mantiene pinneado visualmente en esa posicion y vuelve ahi en cada refresco.
- Muestra un icono musical en la bandeja del sistema mientras esta activo.
- Usa iconos de Windows en vez de botones con texto.
- Muestra titulo, artista, album y caratula si el reproductor activo publica metadata al sistema.
- Actualiza metadata y estado play/pausa por eventos del sistema multimedia cuando estan disponibles.
- Envia comandos multimedia globales a Windows:
  - anterior
  - reproducir / pausar
  - siguiente

## Como ejecutarlo

Doble click en:

```text
Reproductor Taskbar.vbs
```

Ese lanzador abre el widget sin dejar una terminal visible.

Para iniciarlo automaticamente con Windows, doble click en:

```text
install-startup.vbs
```

Para quitar el inicio automatico:

```text
remove-startup.vbs
```

O desde PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\TaskbarMusicWidget.ps1
```

## Limitacion importante

Este prototipo no se inserta realmente dentro de la taskbar. Se superpone visualmente sobre esa zona. Para integrarse de verdad dentro de Explorer/taskbar harian falta hooks, inyeccion o APIs no publicas del shell, que es el terreno donde trabaja Windhawk.
